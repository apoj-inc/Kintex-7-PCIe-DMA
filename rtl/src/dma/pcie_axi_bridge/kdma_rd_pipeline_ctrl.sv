import kdma_pcie_headers_pkg::*;

module kdma_rd_pipeline_ctrl #(
    parameter DMA_CHANNEL_COUNT = 8,
    parameter PIPELINE_CAPACITY = 4,

    parameter ID_W = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)
) (
    input  logic                          clk                                      ,
    input  logic                          rst_n                                    ,

    input  logic [DMA_CHANNEL_COUNT-1:0]  arvalid_i                                ,
    output logic [DMA_CHANNEL_COUNT-1:0]  arready_o                                ,
    input  logic [63:0]                   araddr_i              [DMA_CHANNEL_COUNT],
    input  logic [7:0]                    arlen_i               [DMA_CHANNEL_COUNT],
    input  logic [ID_W-1:0]               arid_i                [DMA_CHANNEL_COUNT],
    input  logic [1:0]                    arburst_i             [DMA_CHANNEL_COUNT],
    input  logic [2:0]                    arsize_i              [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0]  err_valid_o                              ,
    input  logic [DMA_CHANNEL_COUNT-1:0]  err_ready_i                              ,
    output logic [ID_W-1:0]               err_id_o              [DMA_CHANNEL_COUNT],
    output logic [7:0]                    err_len_o             [DMA_CHANNEL_COUNT],

    output logic [ID_W-1:0]               fifo_mux_sel_o        [DMA_CHANNEL_COUNT],
    output logic                          fifo_gate_o           [DMA_CHANNEL_COUNT],

    input  logic [DMA_CHANNEL_COUNT-1:0]  id_fifo_snoop_valid_i                    ,
    input  logic [DMA_CHANNEL_COUNT-1:0]  id_fifo_snoop_ready_i                    ,
    input  logic [DMA_CHANNEL_COUNT-1:0]  id_fifo_snoop_last_i                     ,

    output logic [DMA_CHANNEL_COUNT-1:0]  pcie_valid_o                             ,
    input  logic [DMA_CHANNEL_COUNT-1:0]  pcie_ready_i                             ,
    output logic [127:0]                  pcie_data_o           [DMA_CHANNEL_COUNT],
    output logic [15:0]                   pcie_tkeep_o          [DMA_CHANNEL_COUNT],
    output logic [DMA_CHANNEL_COUNT-1:0]  pcie_tlast_o                             ,

    input  logic [7:0]                    bus_number_i                             ,
    input  logic [4:0]                    device_number_i                          ,
    input  logic [2:0]                    function_number_i                        
);

    generate
        genvar i;

        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : dma_channels
            logic [PIPELINE_CAPACITY-1:0] id_busy;
            logic [ID_W-1:0] exp_id;

            logic pipeline_fifo_valid_rd, pipeline_fifo_ready_rd;

            header_dw0_t hdw0;
            memory_request_3dw_12_t mr3;
            memory_request_4dw_123_t mr4;

            assign fifo_mux_sel_o[i] = pipeline_fifo_valid_rd ? exp_id : '0;
            assign fifo_gate_o[i] = pipeline_fifo_valid_rd;
            assign pcie_tlast_o[i] = '1;

            stream_fifo #(
                .DATA_WIDTH (ID_W              ),
                .FIFO_DEPTH (PIPELINE_CAPACITY )
            ) u_stream_fifo_pipeline (
                .ACLK    (clk  ),
                .ARESETn (rst_n),
                
                .data_i  ({arid_i[i]}),
                .valid_i (pcie_valid_o[i] & pcie_ready_i[i]),
                .ready_o (),
                .free_o  (),

                .data_o  ({exp_id}),
                .valid_o (pipeline_fifo_valid_rd),
                .ready_i (pipeline_fifo_ready_rd),
                .count_o ()
            );

            always_comb begin
                if (id_fifo_snoop_valid_i[i] && id_fifo_snoop_ready_i[i]) begin
                    if (id_fifo_snoop_last_i[i]) begin
                        pipeline_fifo_ready_rd = '1;
                    end
                    else begin
                        pipeline_fifo_ready_rd = '0;
                    end
                end
                else begin
                    pipeline_fifo_ready_rd = '0;
                end
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    id_busy <= '0;
                end
                else begin
                    if (pcie_valid_o[i] && pcie_ready_i[i]) begin
                        id_busy[arid_i[i]] <= '1;
                    end
                    else begin
                        if (id_fifo_snoop_valid_i[i] && id_fifo_snoop_ready_i[i]) begin
                            if (id_fifo_snoop_last_i[i]) begin
                                id_busy[exp_id] <= '0;
                            end
                        end
                    end
                end
            end

            always_comb begin
                if (id_busy[arid_i[i]] == '0) begin
                    arready_o[i]    = ((arburst_i[i] == 2'b01) && (arsize_i[i] == 3'b100)) ? pcie_ready_i[i] : err_ready_i[i];
                    pcie_valid_o[i] = ((arburst_i[i] == 2'b01) && (arsize_i[i] == 3'b100)) ? arvalid_i[i] : '0;
                    err_valid_o[i]  = ((arburst_i[i] == 2'b01) && (arsize_i[i] == 3'b100)) ? '0 : arvalid_i[i];
                end
                else begin
                    arready_o[i]    = '0;
                    pcie_valid_o[i] = '0;
                    err_valid_o[i]  = '0;
                end
            end

            always_comb begin
                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.qos, hdw0.rsvd_0, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                {hdw0.fmt, hdw0.tp} = araddr_i[i][63:32] == '0 ? RD_32 : RD_64;
                hdw0.length = arlen_i[i] >> 2;

                mr3.addr   = {araddr_i[i][31:4], 2'b0};
                mr3.rsvd   = '0;
                mr3.req_id = {bus_number_i, device_number_i, function_number_i};
                mr3.tag    = (i << ID_W) | arid_i[i];
                mr3.ldw_be = '1;
                mr3.fdw_be = '1;

                {mr4.addr_hi, mr4.addr_lo} = {araddr_i[i][63:4], 2'b0};
                mr4.rsvd   = '0;
                mr4.req_id = {bus_number_i, device_number_i, function_number_i};
                mr4.tag    = (i << ID_W) | arid_i[i];
                mr4.ldw_be = '1;
                mr4.fdw_be = '1;

                pcie_data_o[i]  = araddr_i[i][63:32] == '0 ? {32'h0, mr3, hdw0} : {mr4, hdw0};
                pcie_tkeep_o[i] = araddr_i[i][63:32] == '0 ? 16'h0FFF : 16'hFFFF;

                err_id_o[i]  = arid_i[i] ;
                err_len_o[i] = arlen_i[i];
            end
        end
    endgenerate
    
endmodule
