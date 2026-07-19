module tb_axi_bridge;

parameter BAR_COUNT         = 4;

parameter DMA_CHANNEL_COUNT = 8;
parameter PIPELINE_CAPACITY = 4;

parameter AXI_ADDR_WIDTH    = 64 ;
parameter AXI_DATA_WIDTH    = 128;

parameter TOTAL_ID_COUNT = DMA_CHANNEL_COUNT * PIPELINE_CAPACITY                 ;
parameter AXI_ID_WIDTH   = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY);

parameter int DMA_WQ_DEPTH [DMA_CHANNEL_COUNT] = '{8{1024}};
parameter int DMA_RQ_DEPTH [DMA_CHANNEL_COUNT] = '{8{1024}};
parameter     DMA_TQ_DEPTH                     = 8         ;
parameter     MAX_WQ_DEPTH                     = 1024      ;
parameter     MAX_RQ_DEPTH                     = 1024      ;
parameter     DMA_WQ_ADDR_WIDTH                = $clog2(MAX_WQ_DEPTH);
parameter     DMA_RQ_ADDR_WIDTH                = $clog2(MAX_RQ_DEPTH);
parameter     DMA_TQ_ADDR_WIDTH                = $clog2(DMA_TQ_DEPTH);


logic [128+5+5+8 - 1:0] pcie_data_queue [$];
logic test_done;

logic                         clk                                  ;
logic                         rst_n                                ;

logic                         pcie_valid_i                         ;
logic                         pcie_ready_o                         ;
logic [127:0]                 pcie_data_i                          ;
logic [4:0]                   pcie_sof_i                           ;
logic [4:0]                   pcie_eof_i                           ;
logic [7:0]                   pcie_bar_hit_i                       ;

logic                         pcie_valid_o                         ;
logic                         pcie_ready_i                         ;
logic [127:0]                 pcie_data_o                          ;
logic [15:0]                  pcie_tkeep_o                         ;
logic                         pcie_tlast_o                         ;

logic [BAR_COUNT-1:0]         bar_psel_o                           ;
logic                         bar_penable_o                        ;
logic [BAR_COUNT-1:0]         bar_pready_i                         ;
logic [63:0]                  bar_paddr_o                          ;
logic                         bar_pwrite_o                         ;
logic [127:0]                 bar_pwdata_o                         ;
logic [15:0]                  bar_pstrb_o                          ;
logic [127:0]                 bar_prdata_i      [BAR_COUNT]        ;

logic [DMA_CHANNEL_COUNT-1:0] arvalid_i                            ;
logic [DMA_CHANNEL_COUNT-1:0] arready_o                            ;
logic [AXI_ADDR_WIDTH-1:0]    araddr_i          [DMA_CHANNEL_COUNT];
logic [7:0]                   arlen_i           [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      arid_i            [DMA_CHANNEL_COUNT];
logic [1:0]                   arburst_i         [DMA_CHANNEL_COUNT];
logic [2:0]                   arsize_i          [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] rvalid_o                             ;
logic [DMA_CHANNEL_COUNT-1:0] rready_i                             ;
logic [AXI_DATA_WIDTH-1:0]    rdata_o           [DMA_CHANNEL_COUNT];
logic [DMA_CHANNEL_COUNT-1:0] rlast_o                              ;
logic [2:0]                   rresp_o           [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      rid_o             [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] awvalid_i                            ;
logic [DMA_CHANNEL_COUNT-1:0] awready_o                            ;
logic [63:0]                  awaddr_i          [DMA_CHANNEL_COUNT];
logic [7:0]                   awlen_i           [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      awid_i            [DMA_CHANNEL_COUNT];
logic [1:0]                   awburst_i         [DMA_CHANNEL_COUNT];
logic [2:0]                   awsize_i          [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] wvalid_i                             ;
logic [DMA_CHANNEL_COUNT-1:0] wready_o                             ;
logic [127:0]                 wdata_i           [DMA_CHANNEL_COUNT];
logic [DMA_CHANNEL_COUNT-1:0] wlast_i           [DMA_CHANNEL_COUNT];
logic [15:0]                  wstrb_i           [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] bvalid_o                             ;
logic [DMA_CHANNEL_COUNT-1:0] bready_i                             ;
logic [AXI_ID_WIDTH-1:0]      bid_o             [DMA_CHANNEL_COUNT];
logic [2:0]                   bresp_o           [DMA_CHANNEL_COUNT];

logic [7:0]                   bus_number_i                         ;
logic [4:0]                   device_number_i                      ;
logic [2:0]                   function_number_i                    ;


logic [DMA_WQ_ADDR_WIDTH:0] dmawr_data_count_i [DMA_CHANNEL_COUNT];
logic [DMA_RQ_ADDR_WIDTH:0] dmard_data_free_i  [DMA_CHANNEL_COUNT];

assign bar_pready_i[1] = '0;
assign bar_pready_i[3] = '0;
assign bar_prdata_i[1] = '0;
assign bar_prdata_i[3] = '0;

initial begin
    for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
        dmawr_data_count_i[i] = i * 3;
        dmard_data_free_i [i] = i * 3;
    end
end

assign {bus_number_i, device_number_i, function_number_i} = 16'hDEAD;

kdma_pcie_axi_bridge #(
    .BAR_COUNT         (BAR_COUNT        ),

    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
    .PIPELINE_CAPACITY (PIPELINE_CAPACITY),

    .AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH   ),
    .AXI_DATA_WIDTH    (AXI_DATA_WIDTH   )
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

    .bar_psel_o        (bar_psel_o       ),
    .bar_penable_o     (bar_penable_o    ),
    .bar_pready_i      (bar_pready_i     ),
    .bar_paddr_o       (bar_paddr_o      ),
    .bar_pwrite_o      (bar_pwrite_o     ),
    .bar_pwdata_o      (bar_pwdata_o     ),
    .bar_pstrb_o       (bar_pstrb_o      ),
    .bar_prdata_i      (bar_prdata_i     ),

    .arvalid_i         (arvalid_i        ),
    .arready_o         (arready_o        ),
    .araddr_i          (araddr_i         ),
    .arlen_i           (arlen_i          ),
    .arid_i            (arid_i           ),
    .arburst_i         (arburst_i        ),
    .arsize_i          (arsize_i         ),

    .rvalid_o          (rvalid_o         ),
    .rready_i          (rready_i         ),
    .rdata_o           (rdata_o          ),
    .rlast_o           (rlast_o          ),
    .rresp_o           (rresp_o          ),
    .rid_o             (rid_o            ),

    .awvalid_i         (awvalid_i        ),
    .awready_o         (awready_o        ),
    .awaddr_i          (awaddr_i         ),
    .awlen_i           (awlen_i          ),
    .awid_i            (awid_i           ),
    .awburst_i         (awburst_i        ),
    .awsize_i          (awsize_i         ),

    .wvalid_i          (wvalid_i         ),
    .wready_o          (wready_o         ),
    .wdata_i           (wdata_i          ),
    .wlast_i           (wlast_i          ),
    .wstrb_i           (wstrb_i          ),

    .bvalid_o          (bvalid_o         ),
    .bready_i          (bready_i         ),
    .bid_o             (bid_o            ),
    .bresp_o           (bresp_o          ),

    .bus_number_i      (bus_number_i     ),
    .device_number_i   (device_number_i  ),
    .function_number_i (function_number_i)

);

kdma_msix_flatten #(
    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
) u_kdma_msix_flatten (
    .clk               (clk            ),
    .rst_n             (rst_n          ),

    .bar_psel_i        (bar_psel_o[0]  ),
    .bar_penable_i     (bar_penable_o  ),
    .bar_pready_o      (bar_pready_i[0]),
    .bar_paddr_i       (bar_paddr_o    ),
    .bar_pwrite_i      (bar_pwrite_o   ),
    .bar_pwdata_i      (bar_pwdata_o   ),
    .bar_pstrb_i       (bar_pstrb_o    ),
    .bar_prdata_o      (bar_prdata_i[0]),

    .dma_msix_mask_o   (),
    .dma_msix_data_o   (),
    .dma_msix_addrs_o  (),

    .user_msix_mask_o  (),
    .user_msix_data_o  (),
    .user_msix_addrs_o ()
);

kdma_csr_flatten #(
    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
) u_kdma_csr_flatten (
    .clk                (clk            ),
    .rst_n              (rst_n          ),

    .bar_psel_i         (bar_psel_o[2]  ),
    .bar_penable_i      (bar_penable_o  ),
    .bar_pready_o       (bar_pready_i[2]),
    .bar_paddr_i        (bar_paddr_o    ),
    .bar_pwrite_i       (bar_pwrite_o   ),
    .bar_pwdata_i       (bar_pwdata_o   ),
    .bar_pstrb_i        (bar_pstrb_o    ),
    .bar_prdata_o       (bar_prdata_i[2]),

    .dma_reset_o        (),
    .dmawr_irq_clr_o    (),
    .dmard_irq_clr_o    (),
    .dma_addr_o         (),

    .dmawr_task_free_i  (4'h2),
    .dmard_task_free_i  (4'h5),
    .dmawr_data_count_i (dmawr_data_count_i),
    .dmard_data_free_i  (dmard_data_free_i ),
    .dmawr_irq_sts_i    (8'hde),
    .dmard_irq_sts_i    (8'h01)
);

always #4 clk = ~clk;

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
        {pcie_data_i, pcie_sof_i, pcie_eof_i, pcie_bar_hit_i} <= pcie_data_queue.pop_front();
    end
    else begin
        pcie_valid_i <= (pcie_valid_i && ~pcie_ready_o) ? '1 : $urandom();
        if (pcie_valid_i && pcie_ready_o) begin
            {pcie_data_i, pcie_sof_i, pcie_eof_i, pcie_bar_hit_i} <= pcie_data_queue.pop_front();
        end
    end
end

initial begin
    test_done = 0;

    
    arvalid_i = '0;
    rready_i  = '0;
    awvalid_i = '0;
    wvalid_i  = '0;
    bready_i  = '0;

    clk = 1;
    rst_n = 1;

    #2;
    rst_n = 0;

    #2;
    rst_n = 1;
    
    while (pcie_data_queue.size()) begin
        @(posedge clk);
    end

    repeat (100) @(posedge clk);
    
    test_done = 1;
end

header_dw0_t             hdw0, hdw0_in, hdw0_out;
memory_request_3dw_12_t  mr3d, mr3d_in, mr3d_out;
memory_request_4dw_123_t mr4d, mr4d_in, mr4d_out;
cpl_3dw_12_t             cpl3, cpl3_in, cpl3_out;

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
    for (int bar = 'b11; bar <= 'b1100; bar = bar << 2) begin
        for (int i = 1; i <= 4; i++) begin
            for (int j = 0; j < 4 - i + 1; j++) begin
                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                {hdw0.fmt, hdw0.tp} = WR_32;
                hdw0.length = i;
                
                mr3d.addr = (bar == 'b0011) ? (j*4) >> 2 : ('h40 + j*4) >> 2;
                mr3d.rsvd = '0;
                mr3d.ldw_be = hdw0.length == 1 ? '0 : '1;
                mr3d.fdw_be = '1;
                mr3d.tag = $urandom();

                $display("Transaction WR_32: addr %x, id %x, tag %x", {mr3d.addr, 2'h0}, mr3d.req_id, mr3d.tag);

                if (i == 1) begin
                    pcie_data_queue.push_back({$urandom(), mr3d, hdw0, 5'b10000, 5'b11111, 8'(bar)});
                end
                else begin
                    pcie_data_queue.push_back({$urandom(), mr3d, hdw0, 5'b10000, 5'b00000, 8'(bar)});
                    pcie_data_queue.push_back({$urandom(), $urandom(), $urandom(), $urandom(), 5'b00000, 1'b1, 4'((i-1)*4 - 1), 8'(bar)});
                end
            end
        end
        
        for (int i = 1; i <= 4; i++) begin
            for (int j = 0; j < 4 - i + 1; j++) begin
                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                {hdw0.fmt, hdw0.tp} = RD_32;
                hdw0.length = i;
                
                mr3d.addr = (bar == 'b0011) ? (j*4) >> 2 : ('h40 + j*4) >> 2;
                {mr3d.rsvd, mr3d.ldw_be} = '0;
                mr3d.fdw_be = '1;
                mr3d.tag = $urandom();

                $display("Transaction RD_32: addr %x, id %x, tag %x", {mr3d.addr, 2'h0}, mr3d.req_id, mr3d.tag);
                pcie_data_queue.push_back({32'b0, mr3d, hdw0, 5'b10000, 5'b11011, 8'(bar)});
            end
        end
        
        for (int i = 1; i <= 4; i++) begin
            for (int j = 0; j < 4 - i + 1; j++) begin
                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                {hdw0.fmt, hdw0.tp} = WR_64;
                hdw0.length = i;

                mr4d.addr_lo = (bar == 'b0011) ? (j*4) >> 2 : ('h40 + j*4) >> 2;
                mr4d.addr_hi = '0;
                mr4d.rsvd = '0;
                mr4d.ldw_be = hdw0.length == 1 ? '0 : '1;
                mr4d.fdw_be = '1;
                mr4d.tag = $urandom();

                $display("Transaction WR_64: addr %x, id %x, tag %x", {mr4d.addr_hi, mr4d.addr_lo}, mr4d.req_id, mr4d.tag);
                pcie_data_queue.push_back({mr4d, hdw0, 5'b10000, 5'b00000, 8'(bar)});
                pcie_data_queue.push_back({32'($urandom()), 32'($urandom()),32'($urandom()), 32'($urandom()),  5'b00000, 1'b1, 4'((hdw0.length)*4-1), 8'(bar)});
            end
        end

        for (int i = 1; i <= 4; i++) begin
            for (int j = 0; j < 4 - i + 1; j++) begin
                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                {hdw0.fmt, hdw0.tp} = RD_64;
                hdw0.length = i;
                
                mr4d.addr_lo = (bar == 'b0011) ? (j*4) >> 2 : ('h40 + j*4) >> 2;
                mr4d.addr_hi = '0;
                {mr4d.rsvd, mr4d.ldw_be} = '0;
                mr4d.fdw_be = '1;
                mr4d.tag = $urandom();

                $display("Transaction RD_64: addr %x, id %x, tag %x", {mr4d.addr_hi, mr4d.addr_lo}, mr4d.req_id, mr4d.tag);
                pcie_data_queue.push_back({mr4d, hdw0, 5'b10000, 5'b11111, 8'(bar)});
            end
        end
    end
end

endmodule