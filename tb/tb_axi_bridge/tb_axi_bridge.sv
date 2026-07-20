import kdma_pcie_headers_pkg::*;

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


semaphore pcie_data_lock;

logic [128+5+5+8 - 1:0] pcie_data_queue [$];
logic reg_acc_test_done;

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

logic                         arvalid           [DMA_CHANNEL_COUNT];
logic                         arready           [DMA_CHANNEL_COUNT];
logic [AXI_ADDR_WIDTH-1:0]    araddr            [DMA_CHANNEL_COUNT];
logic [7:0]                   arlen             [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      arid              [DMA_CHANNEL_COUNT];
logic [1:0]                   arburst           [DMA_CHANNEL_COUNT];
logic [2:0]                   arsize            [DMA_CHANNEL_COUNT];

logic                         rvalid            [DMA_CHANNEL_COUNT];
logic                         rready            [DMA_CHANNEL_COUNT];
logic [AXI_DATA_WIDTH-1:0]    rdata             [DMA_CHANNEL_COUNT];
logic                         rlast             [DMA_CHANNEL_COUNT];
logic [2:0]                   rresp             [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      rid               [DMA_CHANNEL_COUNT];

logic                         awvalid           [DMA_CHANNEL_COUNT];
logic                         awready           [DMA_CHANNEL_COUNT];
logic [63:0]                  awaddr            [DMA_CHANNEL_COUNT];
logic [7:0]                   awlen             [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      awid              [DMA_CHANNEL_COUNT];
logic [1:0]                   awburst           [DMA_CHANNEL_COUNT];
logic [2:0]                   awsize            [DMA_CHANNEL_COUNT];

logic                         wvalid            [DMA_CHANNEL_COUNT];
logic                         wready            [DMA_CHANNEL_COUNT];
logic [127:0]                 wdata             [DMA_CHANNEL_COUNT];
logic                         wlast             [DMA_CHANNEL_COUNT];
logic [15:0]                  wstrb             [DMA_CHANNEL_COUNT];

logic                         bvalid            [DMA_CHANNEL_COUNT];
logic                         bready            [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      bid               [DMA_CHANNEL_COUNT];
logic [2:0]                   bresp             [DMA_CHANNEL_COUNT];

logic [7:0]                   bus_number_i                         ;
logic [4:0]                   device_number_i                      ;
logic [2:0]                   function_number_i                    ;


logic [DMA_CHANNEL_COUNT-1:0] arvalid_pkd;
logic [DMA_CHANNEL_COUNT-1:0] arready_pkd;
logic [DMA_CHANNEL_COUNT-1:0] rvalid_pkd ;
logic [DMA_CHANNEL_COUNT-1:0] rready_pkd ;
logic [DMA_CHANNEL_COUNT-1:0] rlast_pkd  ;
logic [DMA_CHANNEL_COUNT-1:0] awvalid_pkd;
logic [DMA_CHANNEL_COUNT-1:0] awready_pkd;
logic [DMA_CHANNEL_COUNT-1:0] wvalid_pkd ;
logic [DMA_CHANNEL_COUNT-1:0] wready_pkd ;
logic [DMA_CHANNEL_COUNT-1:0] wlast_pkd  ;
logic [DMA_CHANNEL_COUNT-1:0] bvalid_pkd ;
logic [DMA_CHANNEL_COUNT-1:0] bready_pkd ;

generate
    for (genvar i = 0; i < DMA_CHANNEL_COUNT; i++) begin
        assign arvalid_pkd[i] = arvalid[i];
        assign rready_pkd [i] = rready [i];
        assign awvalid_pkd[i] = awvalid[i];
        assign wvalid_pkd [i] = wvalid [i];
        assign wlast_pkd  [i] = wlast  [i];
        assign bready_pkd [i] = bready [i];
        assign arready[i] = arready_pkd[i];
        assign rvalid [i] = rvalid_pkd [i];
        assign rlast  [i] = rlast_pkd  [i];
        assign awready[i] = awready_pkd[i];
        assign wready [i] = wready_pkd [i];
        assign bvalid [i] = bvalid_pkd [i];
    end
endgenerate


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

    .arvalid_i         (arvalid_pkd      ),
    .arready_o         (arready_pkd      ),
    .araddr_i          (araddr           ),
    .arlen_i           (arlen            ),
    .arid_i            (arid             ),
    .arburst_i         (arburst          ),
    .arsize_i          (arsize           ),

    .rvalid_o          (rvalid_pkd       ),
    .rready_i          (rready_pkd       ),
    .rdata_o           (rdata            ),
    .rlast_o           (rlast_pkd        ),
    .rresp_o           (rresp            ),
    .rid_o             (rid              ),

    .awvalid_i         (awvalid_pkd      ),
    .awready_o         (awready_pkd      ),
    .awaddr_i          (awaddr           ),
    .awlen_i           (awlen            ),
    .awid_i            (awid             ),
    .awburst_i         (awburst          ),
    .awsize_i          (awsize           ),

    .wvalid_i          (wvalid_pkd       ),
    .wready_o          (wready_pkd       ),
    .wdata_i           (wdata            ),
    .wlast_i           (wlast_pkd        ),
    .wstrb_i           (wstrb            ),

    .bvalid_o          (bvalid_pkd       ),
    .bready_i          (bready_pkd       ),
    .bid_o             (bid              ),
    .bresp_o           (bresp            ),

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


initial begin
    reg_acc_test_done = 0;

    
    arvalid = '{default: '0};
    rready  = '{default: '0};
    awvalid = '{default: '0};
    wvalid  = '{default: '0};
    bready  = '{default: '0};

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
    
    reg_acc_test_done = 1;
end

header_dw0_t             hdw0, hdw0_event, hdw0_in, hdw0_out;
memory_request_3dw_12_t  mr3d, mr3d_event, mr3d_in, mr3d_out;
memory_request_4dw_123_t mr4d, mr4d_event, mr4d_in, mr4d_out;
cpl_3dw_12_t             cpl3, cpl3_event, cpl3_in, cpl3_out;

logic tlast_was;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tlast_was <= '0;
    end
    else begin
        if (pcie_valid_o && pcie_ready_i) begin
            tlast_was <= pcie_tlast_o;
        end
    end
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

always @(posedge clk) begin
    if (pcie_valid_o && pcie_ready_i) begin
        if (tlast_was) begin
            case ({hdw0_out.fmt, hdw0_out.tp})
                RD_32, RD_64: begin
                    pcie_data_lock.get(1);
                    $display("Processing read request...", $time);
                    {hdw0_event.rsvd_2, hdw0_event.rsvd_1, hdw0_event.rsvd_0, hdw0_event.qos, hdw0_event.digest, hdw0_event.err, hdw0_event.attr, hdw0_event.addr_tran} = '0;
                    {hdw0_event.fmt, hdw0_event.tp} = CPLD;
                    if (hdw0_out.length == 4) begin
                        hdw0_event.length = hdw0_out.length;
                    end
                    else if ((hdw0_out.length / 2) % 4 != 0) begin
                        hdw0_event.length = hdw0_out.length / 2 + 2;
                    end
                    else begin
                        hdw0_event.length = hdw0_out.length / 2;
                    end

                    cpl3_event.req_id   = mr3d_out.req_id;
                    cpl3_event.tag      = mr3d_out.tag;
                    cpl3_event.rsvd     = '0;
                    cpl3_event.addr_lo  = '0;
                    cpl3_event.cpl_id   = $urandom();
                    cpl3_event.cpl_sts  = '0;
                    cpl3_event.bcm      = '0;
                    cpl3_event.byte_cnt = hdw0_out.length << 2;

                    pcie_data_queue.push_back({$urandom(), cpl3_event, hdw0_event, 5'b10000, 5'b00000, 8'h0});
                    for (int i = 0; i <= (hdw0_event.length - 1) / 4; i++) begin
                        pcie_data_queue.push_back({$urandom(), $urandom(), $urandom(), $urandom(), 5'b00000, 1'(i == (hdw0_event.length - 1) / 4), 4'b1011, 8'h0});
                    end
                    if (hdw0_out.length != 4) begin
                        if ((hdw0_out.length / 2) % 4 != 0) begin
                            hdw0_event.length = hdw0_out.length / 2 - 2;
                        end
                        else begin
                            hdw0_event.length = hdw0_out.length / 2;
                        end

                        cpl3_event.req_id   = mr3d_out.req_id;
                        cpl3_event.tag      = mr3d_out.tag;
                        cpl3_event.rsvd     = '0;
                        cpl3_event.addr_lo  = '0;
                        cpl3_event.cpl_id   = $urandom();
                        cpl3_event.cpl_sts  = '0;
                        cpl3_event.bcm      = '0;
                        cpl3_event.byte_cnt = hdw0_event.length << 2;

                        pcie_data_queue.push_back({$urandom(), cpl3_event, hdw0_event, 5'b10000, 5'b00000, 8'h0});
                        for (int i = 0; i <= (hdw0_event.length - 1) / 4; i++) begin
                            pcie_data_queue.push_back({$urandom(), $urandom(), $urandom(), $urandom(), 5'b00000, 1'(i == (hdw0_event.length - 1) / 4), 4'b1011, 8'h0});
                        end
                    end

                    pcie_data_lock.put(1);
                end 
                default: begin
                end
            endcase
        end
    end
end

initial begin
    pcie_data_lock = new(1);

    pcie_data_lock.get(1);
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
    pcie_data_lock.put(1);
end

endmodule