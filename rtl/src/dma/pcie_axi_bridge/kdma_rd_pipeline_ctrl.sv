module kdma_rd_pipeline_ctrl #(
    parameter DMA_CHANNEL_COUNT = 8,
    parameter PIPELINE_CAPACITY = 4,

    parameter TOTAL_ID_COUNT     = DMA_CHANNEL_COUNT * PIPELINE_CAPACITY,
    parameter TOTAL_ID_COUNT_W   = TOTAL_ID_COUNT == 1 ? 1 : $clog2(TOTAL_ID_COUNT),
    parameter ID_LOWER_BYTECOUNT = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)
) (
    input  logic                          clk                                      ,
    input  logic                          rst_n                                    ,

    input  logic                          arvalid_i             [DMA_CHANNEL_COUNT],
    output logic                          arready_o             [DMA_CHANNEL_COUNT],
    input  logic [63:0]                   araddr_i              [DMA_CHANNEL_COUNT],
    input  logic [7:0]                    arlen_i               [DMA_CHANNEL_COUNT],
    input  logic [2:0]                    arsize_i              [DMA_CHANNEL_COUNT],
    input  logic [1:0]                    arburst_i             [DMA_CHANNEL_COUNT],
    input  logic [TOTAL_ID_COUNT_W-1:0]   arid_i                [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0]  fifo_mux_sel_o                           ,

    input  logic [DMA_CHANNEL_COUNT-1:0]  id_fifo_snoop_valid_i                    ,
    input  logic [DMA_CHANNEL_COUNT-1:0]  id_fifo_snoop_ready_i                    ,

    output logic [DMA_CHANNEL_COUNT-1:0]  err_o                                    ,
    output logic [ID_LOWER_BYTECOUNT-1:0] err_id_o              [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0]  err_clr_i                                ,

    output logic [DMA_CHANNEL_COUNT-1:0]  pcie_valid_o                             ,
    input  logic [DMA_CHANNEL_COUNT-1:0]  pcie_ready_i                             ,
    output logic [127:0]                  pcie_header_o         [DMA_CHANNEL_COUNT],

    input  logic [7:0]                    bus_number_i                             ,
    input  logic [4:0]                    device_number_i                          ,
    input  logic [2:0]                    function_number_i                        
);

    generate
        genvar i;

        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : dma_channels
            logic [ID_LOWER_BYTECOUNT-1:0] id_busy;

            logic pipeline_fifo_ready_wr;
            logic pipeline_fifo_valid_rd, pipeline_fifo_ready_rd;

            logic exp_id, exp_len;

            logic [9:0] snoop_counter;

            logic [31:0] pcie_header_dwords [4];

            logic         pcie_valid_fifo_wr ;
            logic [127:0] pcie_header_fifo_wr;

            assign fifo_mux_sel_o[i] = pipeline_fifo_valid_rd ? exp_id[ID_LOWER_BYTECOUNT-1:0] : '0;

            stream_fifo #(
                .DATA_WIDTH (TOTAL_ID_COUNT_W ),
                .FIFO_DEPTH (PIPELINE_CAPACITY)
            ) u_stream_fifo_pipeline (
                .ACLK    (clk  )
                .ARESETn (rst_n)
                
                .data_i  ({arlen_i[i], arid_i[i]})
                .valid_i (arvalid_i[i] & arready_o[i])
                .ready_o (pipeline_fifo_ready_wr)
                .free_o  ()

                .data_o  ({exp_len, exp_id})
                .valid_o (pipeline_fifo_valid_rd)
                .ready_i (pipeline_fifo_ready_rd)
                .count_o ()
            );

            stream_fifo #(
                .DATA_WIDTH (128),
                .FIFO_DEPTH (PIPELINE_CAPACITY)
            ) u_stream_fifo_to_pcie (
                .ACLK    (clk  )
                .ARESETn (rst_n)
                
                .data_i  (pcie_header_fifo_wr)
                .valid_i (pcie_valid_fifo_wr )
                .ready_o ()
                .free_o  ()

                .data_o  (pcie_header_o[i])
                .valid_o (pcie_valid_o[i] )
                .ready_i (pcie_ready_i[i] )
                .count_o ()
            );

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    snoop_counter <= '0;
                    pipeline_fifo_ready_rd <= '0;
                end
                else begin
                    if (id_fifo_snoop_valid_i[i] && id_fifo_snoop_ready_i[i]) begin
                        if (snoop_counter + 1 == exp_len) begin
                            snoop_counter <= '0;
                            pipeline_fifo_ready_rd <= '1;
                        end
                        else begin
                            snoop_counter <= snoop_counter + 1;
                            pipeline_fifo_ready_rd <= '0;
                        end
                    end
                    else begin
                        pipeline_fifo_ready_rd <= '0;
                    end
                end
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    id_busy <= '0;
                end
                else begin
                    if (arvalid_i[i] && arready_o[i]) begin
                        if ((arid_i[i] >> ID_LOWER_BYTECOUNT) == DMA_CHANNEL_COUNT) begin
                            id_busy[arid_i[i][0 +: ID_LOWER_BYTECOUNT]] <= '1;
                        end
                    end
                    else begin
                        if (pipeline_fifo_ready_rd) begin
                            id_busy[arid_i[i][0 +: ID_LOWER_BYTECOUNT]] <= '0;
                        end
                    end
                end
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    arready_o[i] <= '0;
                end
                else begin
                    if ((arid_i[i] >> ID_LOWER_BYTECOUNT) == DMA_CHANNEL_COUNT) begin
                        if (!id_busy[arid_i[i][0 +: ID_LOWER_BYTECOUNT]]) begin
                            arready_o[i] <= pipeline_fifo_ready_wr;
                        end
                        else begin
                            arready_o[i] <= '0;
                        end
                    end
                    else begin
                        arready_o[i] <= '0;
                    end
                end
            end

            always_comb begin
                pcie_header_dwords[0] = {1'h0, 2'b11, 5'h0, 1'b0, 3'h0, 4'h0, 1'h0, 1'h0, 2'h0, 2'h0, 10'(arlen_i)}; // rsvd, fmt, type, rsvd, qos, rsvd, digest, error poison, attribs, rsvd, length
                pcie_header_dwords[1] = {bus_number_i, device_number_i, function_number_i, 8'(arid_i), 4'h0, 4'h0}; // first 3 - req id, tag, last dw be, 1st dw be
                pcie_header_dwords[2] = {araddr_i[63:32]};
                pcie_header_dwords[3] = {araddr_i[31:2], 2'b0}; // 32-bit alignment
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    pcie_valid_fifo_wr <= '0;
                    pcie_header_fifo_wr <= '0;
                end
                else begin
                    pcie_header_fifo_wr <= {pcie_header_dwords[3], pcie_header_dwords[2], pcie_header_dwords[1], pcie_header_dwords[0]}
                    pcie_valid_fifo_wr <= arvalid_i[i] && arready_o[i];
                end
            end
        end
    endgenerate
    
endmodule