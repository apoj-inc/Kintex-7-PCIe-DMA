module tb_dma_echodevice_bridged;

parameter BAR_COUNT                                 = 4         ;

parameter DMA_CHANNEL_COUNT                         = 2         ;
parameter PIPELINE_CAPACITY                         = 4         ;

parameter     DMA_BYTES_WIDTH                       = 22        ;
parameter     DMA_OFFFSET_WIDTH                     = 22        ;

parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{2{16  }};
parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{16  }};
parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{16  }};
parameter     DMA_TQ_DEPTH                          = 2         ;

parameter     MAX_WQ_DEPTH                          = 16        ;
parameter     MAX_RQ_DEPTH                          = 16        ;

parameter AXI_ID_WIDTH   = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY);
parameter MSIX_COUNT     = DMA_CHANNEL_COUNT                                     ;

logic                  clk              ;
logic                  rst_n            ;

logic                  pcie_valid_i     ;
logic                  pcie_ready_o     ;
logic [127:0]          pcie_data_i      ;
logic [4:0]            pcie_sof_i       ;
logic [4:0]            pcie_eof_i       ;
logic [7:0]            pcie_bar_hit_i   ;

logic                  pcie_valid_o     ;
logic                  pcie_ready_i     ;
logic [127:0]          pcie_data_o      ;
logic [15:0]           pcie_tkeep_o     ;
logic                  pcie_tlast_o     ;

logic [7:0]            bus_number_i     ;
logic [4:0]            device_number_i  ;
logic [2:0]            function_number_i;

logic [MSIX_COUNT-1:0] user_irq_i       ;

assign {bus_number_i, device_number_i, function_number_i} = 'hDEAD;

kdma_echodevice_bridged #(
    .BAR_COUNT         (BAR_COUNT        ),

    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
    .PIPELINE_CAPACITY (PIPELINE_CAPACITY),

    .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH  ),
    .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH),

    .DMA_WORD_BYTES    (DMA_WORD_BYTES   ),
    .DMA_WQ_DEPTH      (DMA_WQ_DEPTH     ),
    .DMA_RQ_DEPTH      (DMA_RQ_DEPTH     ),
    .DMA_TQ_DEPTH      (DMA_TQ_DEPTH     ),

    .MAX_WQ_DEPTH      (MAX_WQ_DEPTH     ),
    .MAX_RQ_DEPTH      (MAX_RQ_DEPTH     )
) dut (
    .clk               (clk              ),
    .rst_n             (rst_n            ),

    .pcie_valid_i      (pcie_valid_i     ),
    .pcie_ready_o      (pcie_ready_o     ),
    .pcie_data_i       (pcie_data_i      ),
    .pcie_sof_i        (pcie_sof_i       ),
    .pcie_eof_i        (pcie_eof_i       ),
    .pcie_bar_hit_i    (pcie_bar_hit_i   ),

    .pcie_valid_o      (pcie_valid_o     ),
    .pcie_ready_i      (pcie_ready_i     ),
    .pcie_data_o       (pcie_data_o      ),
    .pcie_tkeep_o      (pcie_tkeep_o     ),
    .pcie_tlast_o      (pcie_tlast_o     ),

    .bus_number_i      (bus_number_i     ),
    .device_number_i   (device_number_i  ),
    .function_number_i (function_number_i),

    .user_irq_i        (user_irq_i       )
);

always #4 clk = ~clk;

logic test_done;

header_dw0_t             hdw0, hdw0_event, hdw0_in, hdw0_out;
memory_request_3dw_12_t  mr3d, mr3d_event, mr3d_in, mr3d_out;
memory_request_4dw_123_t mr4d, mr4d_event, mr4d_in, mr4d_out;
cpl_3dw_12_t             cpl3, cpl3_event, cpl3_in, cpl3_out;

logic [128+5+5+8 - 1:0] pcie_data_queue [$];

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_ready_i <= '0;
    end
    else begin
        pcie_ready_i <= $urandom();
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_valid_i <= '0;
    end
    else begin
        pcie_valid_i <= pcie_data_queue.size() ?
                        (pcie_valid_i && ~pcie_ready_o) ? '1 : $urandom()
                        : '0;
        if (pcie_valid_i && pcie_ready_o) begin
            pcie_data_queue.pop_front();
        end
    end
end

always_comb begin
    {pcie_data_i, pcie_sof_i, pcie_eof_i, pcie_bar_hit_i} = pcie_data_queue[0];
end

assign hdw0_out = pcie_data_o[31:0];
assign mr3d_out = pcie_data_o[95:32];
assign mr4d_out = pcie_data_o[127:32];
assign cpl3_out = pcie_data_o[95:32];

assign hdw0_in = pcie_data_i[31:0];
assign mr3d_in = pcie_data_i[95:32];
assign mr4d_in = pcie_data_i[127:32];
assign cpl3_in = pcie_data_i[95:32];

assign mr3d.req_id = 'hBEEF;
assign mr4d.req_id = 'hBEEF;

initial begin
    test_done = '0;
    clk = 0;
    #2;
    rst_n = 0;
    user_irq_i = '0;

    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    repeat (1000) @(posedge clk);
    
    test_done = '1;
end

initial begin
    {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
    {hdw0.fmt, hdw0.tp} = WR_32;
    hdw0.length = 1;
    
    mr3d.addr = 'h9170000C >> 2;
    mr3d.rsvd = '0;
    mr3d.ldw_be = '0;
    mr3d.fdw_be = '1;
    mr3d.tag = $urandom();

    pcie_data_queue.push_back({8'h1, 8'h0, 8'h0, 8'h0, mr3d, hdw0, 5'b10000, 5'b11111, 8'('b1100)});


    {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
    {hdw0.fmt, hdw0.tp} = WR_32;
    hdw0.length = 2;
    
    mr3d.addr = 'h91701008 >> 2;
    mr3d.rsvd = '0;
    mr3d.ldw_be = '0;
    mr3d.fdw_be = '1;
    mr3d.tag = $urandom();

    pcie_data_queue.push_back({32'h0, mr3d, hdw0, 5'b10000, 5'b0000, 8'('b1100)});

    pcie_data_queue.push_back({96'h0, 8'b0, 8'b0100, 8'b0, 8'b0, 5'b00000, 5'b10011, 8'('b1100)});
end

endmodule