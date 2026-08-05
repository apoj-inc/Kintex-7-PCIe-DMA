module kdma_dmic #(
    parameter MSIX_COUNT        = 8,
    parameter PIPELINE_CAPACITY = 4 ,

    parameter ST_1_GRP_SIZE     = 4 ,

    parameter ST_1_ARB_DIV     = MSIX_COUNT / ST_1_GRP_SIZE                            ,
    parameter ST_1_ARB_REM     = MSIX_COUNT % ST_1_GRP_SIZE                            ,
    parameter ST_1_ARB_CNT     = ST_1_ARB_DIV + (ST_1_ARB_REM != 0)                    ,
    parameter ST_1_GRP_SIZE_W  = ST_1_GRP_SIZE == 1 ? 1 : $clog2(ST_1_GRP_SIZE)        ,
    parameter ST_1_ARB_REM_W   = ST_1_ARB_REM == 1 ? 1 : $clog2(ST_1_ARB_REM)          ,

    parameter MSIX_COUNT_WIDTH = MSIX_COUNT == 1 ? 1 : $clog2(MSIX_COUNT)              ,

    parameter AXI_ID_WIDTH     = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)
) (
    input  logic                    clk                          ,
    input  logic                    rst_n                        ,

    input  logic [MSIX_COUNT-1:0]   irq_i                        ,

    input  logic [31:0]             msix_mask_i      [MSIX_COUNT],
    input  logic [31:0]             msix_data_i      [MSIX_COUNT],
    input  logic [63:0]             msix_addrs_i     [MSIX_COUNT],

    output logic                    msix_awvalid_o               ,
    input  logic                    msix_awready_i               ,
    output logic [63:0]             msix_awaddr_o                ,
    output logic [7:0]              msix_awlen_o                 ,
    output logic [AXI_ID_WIDTH-1:0] msix_awid_o                  ,
    output logic [1:0]              msix_awburst_o               ,
    output logic [2:0]              msix_awsize_o                ,

    output logic                    msix_wvalid_o                ,
    input  logic                    msix_wready_i                ,
    output logic [127:0]            msix_wdata_o                 ,
    output logic                    msix_wlast_o                 ,
    output logic [15:0]             msix_wstrb_o                 ,

    input  logic                    msix_bvalid_i                ,
    output logic                    msix_bready_o                ,
    input  logic [AXI_ID_WIDTH-1:0] msix_bid_i                   ,
    input  logic [1:0]              msix_bresp_i                 
);

    logic [MSIX_COUNT-1:0] irq_ff, irq_pending, irq_clear, irq_pending_to_arb;

    logic [MSIX_COUNT_WIDTH-1:0] irq_index;
    logic send_irq, irq_sent;

    assign msix_awlen_o   = '0;
    assign msix_awid_o    = '0;
    assign msix_awburst_o = 2'b01;
    assign msix_awsize_o  = 3'b100;

    assign msix_wlast_o = '1;

    assign msix_bready_o = '1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_ff <= '0;
        end
        else begin
            irq_ff <= irq_i;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending        <= '0;
            irq_pending_to_arb <= '0;
        end        
        else begin
            irq_pending <= (irq_pending | (~irq_ff & irq_i)) & ~(irq_clear & irq_pending);

            for (int i = 0; i < MSIX_COUNT; i++) begin
                irq_pending_to_arb[i] <= irq_pending[i] & ~msix_mask_i[i][0];
            end
        end
    end


    logic [ST_1_ARB_CNT-1:0]     send_irq_st_1                ;
    logic [ST_1_ARB_CNT-1:0]     irq_sent_st_1                ;
    logic [MSIX_COUNT_WIDTH-1:0] irq_index_st_1 [ST_1_ARB_CNT];
    logic [MSIX_COUNT_WIDTH-1:0] irq_index_norm [ST_1_ARB_CNT];
        
    generate
        genvar i;

        for (i = 0; i < ST_1_ARB_DIV; i++) begin : st_1_arbs
            stream_arbiter #(
                .DATA_WIDTH (1            ),
                .INPUT_NUM  (ST_1_GRP_SIZE),
                .REG_ST     (1            )
            ) u_stream_arbiter (
                .ACLK    (clk                                                   ),
                .ARESETn (rst_n                                                 ),

                .data_i  ('{ST_1_GRP_SIZE{1'b0}}                                ),
                .valid_i (irq_pending_to_arb[i * ST_1_GRP_SIZE +: ST_1_GRP_SIZE]),
                .ready_o (irq_clear         [i * ST_1_GRP_SIZE +: ST_1_GRP_SIZE]),

                .data_o  (                                                      ), // NC
                .valid_o (send_irq_st_1 [i]                                     ),
                .ready_i (irq_sent_st_1 [i]                                     ),
                .sel_o   (irq_index_st_1[i][ST_1_GRP_SIZE_W-1:0]                )
            );

            assign irq_index_st_1[i][MSIX_COUNT_WIDTH-1:ST_1_GRP_SIZE_W] = '0;
        end
        if (ST_1_ARB_REM != 0) begin : st_1_arb_rem
            stream_arbiter #(
                .DATA_WIDTH (1           ),
                .INPUT_NUM  (ST_1_ARB_REM),
                .REG_ST     (1           )
            ) u_stream_arbiter (
                .ACLK    (clk                                                             ),
                .ARESETn (rst_n                                                           ),

                .data_i  ('{ST_1_ARB_REM{1'b0}}                                           ),
                .valid_i (irq_pending_to_arb[ST_1_ARB_DIV * ST_1_GRP_SIZE +: ST_1_ARB_REM]),
                .ready_o (irq_clear         [ST_1_ARB_DIV * ST_1_GRP_SIZE +: ST_1_ARB_REM]),

                .data_o  (                                                                ), // NC
                .valid_o (send_irq_st_1 [ST_1_ARB_DIV]                                    ),
                .ready_i (irq_sent_st_1 [ST_1_ARB_DIV]                                    ),
                .sel_o   (irq_index_st_1[ST_1_ARB_DIV][ST_1_ARB_REM_W-1:0]                )
            );

            assign irq_index_st_1[ST_1_ARB_DIV][MSIX_COUNT_WIDTH-1:ST_1_ARB_REM_W] = '0;
        end

        for (i = 0; i < ST_1_ARB_CNT; i++) begin : st_1_idx_norm
            assign irq_index_norm[i] = irq_index_st_1[i] + i * ST_1_GRP_SIZE;
        end
    endgenerate
    
    stream_arbiter #(
        .DATA_WIDTH (MSIX_COUNT_WIDTH),
        .INPUT_NUM  (ST_1_ARB_CNT    ),
        .REG_ST     (1               )
    ) u_stream_arbiter (
        .ACLK    (clk           ),
        .ARESETn (rst_n         ),

        .data_i  (irq_index_norm),
        .valid_i (send_irq_st_1 ),
        .ready_o (irq_sent_st_1 ),

        .data_o  (irq_index     ),
        .valid_o (send_irq      ),
        .ready_i (irq_sent      )
    );

    logic aw_was, w_was;

    always_ff @(posedge clk or negedge rst_n) begin : blockName
        if (!rst_n) begin
            msix_awvalid_o <= '0;
            msix_awaddr_o  <= '0;

            msix_wvalid_o  <= '0;
            msix_wdata_o   <= '0;
            msix_wstrb_o   <= '0;

            irq_sent <= '0;

            aw_was <= '0;
            w_was  <= '0;
        end
        else begin
            if (send_irq) begin
                if (!aw_was && !w_was) begin
                    msix_awvalid_o <= '1;
                    msix_awaddr_o  <= msix_addrs_i[irq_index];

                    msix_wvalid_o  <= '1;
                    case (msix_addrs_i[irq_index][3:0])
                        4'h0   : begin
                            msix_wdata_o <= msix_data_i[irq_index] << 0 ;
                            msix_wstrb_o <= 16'h000F;
                        end
                        4'h4   : begin
                            msix_wdata_o <= msix_data_i[irq_index] << 32;
                            msix_wstrb_o <= 16'h00F0;
                        end
                        4'h8   : begin
                            msix_wdata_o <= msix_data_i[irq_index] << 64;
                            msix_wstrb_o <= 16'h0F00;
                        end
                        4'hC   : begin
                            msix_wdata_o <= msix_data_i[irq_index] << 96;
                            msix_wstrb_o <= 16'hF000;
                        end
                        default: begin
                            msix_wdata_o <= msix_data_i[irq_index] << 0 ;
                            msix_wstrb_o <= 16'h000F;
                        end
                    endcase

                    if (msix_awvalid_o && msix_awready_i) begin
                        aw_was <= '1;
                        msix_awvalid_o <= '0;
                    end

                    if (msix_wvalid_o && msix_wready_i) begin
                        w_was <= '1;
                        msix_wvalid_o <= '0;
                    end
                end
                else begin
                    if (aw_was) begin
                        if (msix_wvalid_o && msix_wready_i) begin
                            w_was <= '1;
                            msix_wvalid_o <= '0;
                        end
                    end

                    if (w_was) begin
                        if (msix_awvalid_o && msix_awready_i) begin
                            aw_was <= '1;
                            msix_awvalid_o <= '0;
                        end
                    end

                    if (aw_was && w_was) begin
                        if (!irq_sent) begin
                            irq_sent <= '1;
                        end
                        else begin
                            irq_sent <= '0;
                            aw_was <= '0;
                            w_was <= '0;
                        end
                    end
                end
            end
            else begin
                msix_awvalid_o <= '0;
                msix_wvalid_o  <= '0;

                irq_sent <= '0;

                aw_was <= '0;
                w_was  <= '0;
            end
        end
    end
    
endmodule