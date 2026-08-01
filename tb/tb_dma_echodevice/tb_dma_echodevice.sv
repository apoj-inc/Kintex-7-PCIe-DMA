module tb_dma_echodevice;

parameter     DMA_CHANNEL_COUNT                     = 8         ;
parameter     PIPELINE_CAPACITY                     = 4         ;

parameter     DMA_BYTES_WIDTH                       = 22        ;
parameter     DMA_OFFFSET_WIDTH                     = 22        ;

parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{8{16  }};
parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{16  }};
parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{16  }};
parameter     DMA_TQ_DEPTH                          = 8         ;

parameter     MAX_WQ_DEPTH                          = 16        ;
parameter     MAX_RQ_DEPTH                          = 16        ;

parameter MSIX_COUNT              = DMA_CHANNEL_COUNT                                     ;
parameter AXI_ID_WIDTH            = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY);
parameter DMA_WQ_ADDR_WIDTH       = $clog2(MAX_WQ_DEPTH)                                  ;
parameter DMA_RQ_ADDR_WIDTH       = $clog2(MAX_RQ_DEPTH)                                  ;
parameter DMA_TQ_ADDR_WIDTH       = $clog2(DMA_TQ_DEPTH)                                  ;
parameter PBA_COUNT               = MSIX_COUNT / 64 + (MSIX_COUNT % 64 != 0)              ;
parameter DMA_BURST_WIDTH         = DMA_BYTES_WIDTH - 4                                   ;
parameter DMA_CHANNEL_COUNT_WIDTH = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT);


logic                         clk                               ;
logic                         rst_n                             ;

logic                         csr_psel_i                        ;
logic                         csr_penable_i                     ;
logic                         csr_pready_o                      ;
logic [63:0]                  csr_paddr_i                       ;
logic                         csr_pwrite_i                      ;
logic [127:0]                 csr_pwdata_i                      ;
logic [15:0]                  csr_pstrb_i                       ;
logic [127:0]                 csr_prdata_o                      ;

logic                         msix_psel_i                       ;
logic                         msix_penable_i                    ;
logic                         msix_pready_o                     ;
logic [63:0]                  msix_paddr_i                      ;
logic                         msix_pwrite_i                     ;
logic [127:0]                 msix_pwdata_i                     ;
logic [15:0]                  msix_pstrb_i                      ;
logic [127:0]                 msix_prdata_o                     ;

logic                         dec_psel_i                        ;
logic                         dec_penable_i                     ;
logic                         dec_pready_o                      ;
logic [63:0]                  dec_paddr_i                       ;
logic                         dec_pwrite_i                      ;
logic [127:0]                 dec_pwdata_i                      ;
logic [15:0]                  dec_pstrb_i                       ;
logic [127:0]                 dec_prdata_o                      ;

logic [MSIX_COUNT-1:0]        user_irq_i                        ;

logic [DMA_CHANNEL_COUNT-1:0] arvalid_pkd                       ;
logic [DMA_CHANNEL_COUNT-1:0] arready_pkd                       ;
logic [63:0]                  araddr         [DMA_CHANNEL_COUNT];
logic [7:0]                   arlen          [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      arid           [DMA_CHANNEL_COUNT];
logic [1:0]                   arburst        [DMA_CHANNEL_COUNT];
logic [2:0]                   arsize         [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] rvalid_pkd                        ;
logic [DMA_CHANNEL_COUNT-1:0] rready_pkd                        ;
logic [127:0]                 rdata          [DMA_CHANNEL_COUNT];
logic [DMA_CHANNEL_COUNT-1:0] rlast_pkd                         ;
logic [1:0]                   rresp          [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      rid            [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] awvalid_pkd                       ;
logic [DMA_CHANNEL_COUNT-1:0] awready_pkd                       ;
logic [63:0]                  awaddr         [DMA_CHANNEL_COUNT];
logic [7:0]                   awlen          [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      awid           [DMA_CHANNEL_COUNT];
logic [1:0]                   awburst        [DMA_CHANNEL_COUNT];
logic [2:0]                   awsize         [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] wvalid_pkd                        ;
logic [DMA_CHANNEL_COUNT-1:0] wready_pkd                        ;
logic [127:0]                 wdata          [DMA_CHANNEL_COUNT];
logic [DMA_CHANNEL_COUNT-1:0] wlast_pkd                         ;
logic [15:0]                  wstrb          [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] bvalid_pkd                        ;
logic [DMA_CHANNEL_COUNT-1:0] bready_pkd                        ;
logic [AXI_ID_WIDTH-1:0]      bid            [DMA_CHANNEL_COUNT];
logic [1:0]                   bresp          [DMA_CHANNEL_COUNT];

logic                         msix_awvalid                      ;
logic                         msix_awready                      ;
logic [63:0]                  msix_awaddr                       ;
logic [7:0]                   msix_awlen                        ;
logic [AXI_ID_WIDTH-1:0]      msix_awid                         ;
logic [1:0]                   msix_awburst                      ;
logic [2:0]                   msix_awsize                       ;

logic                         msix_wvalid                       ;
logic                         msix_wready                       ;
logic [127:0]                 msix_wdata                        ;
logic                         msix_wlast                        ;
logic [15:0]                  msix_wstrb                        ;

logic                         msix_bvalid                       ;
logic                         msix_bready                       ;
logic [AXI_ID_WIDTH-1:0]      msix_bid                          ;
logic [1:0]                   msix_bresp                        ;

kdma_echodevice #(
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
    
    .clk            (clk            ),
    .rst_n          (rst_n          ),

    .csr_psel_i     (csr_psel_i     ),
    .csr_penable_i  (csr_penable_i  ),
    .csr_pready_o   (csr_pready_o   ),
    .csr_paddr_i    (csr_paddr_i    ),
    .csr_pwrite_i   (csr_pwrite_i   ),
    .csr_pwdata_i   (csr_pwdata_i   ),
    .csr_pstrb_i    (csr_pstrb_i    ),
    .csr_prdata_o   (csr_prdata_o   ),

    .msix_psel_i    (msix_psel_i    ),
    .msix_penable_i (msix_penable_i ),
    .msix_pready_o  (msix_pready_o  ),
    .msix_paddr_i   (msix_paddr_i   ),
    .msix_pwrite_i  (msix_pwrite_i  ),
    .msix_pwdata_i  (msix_pwdata_i  ),
    .msix_pstrb_i   (msix_pstrb_i   ),
    .msix_prdata_o  (msix_prdata_o  ),

    .dec_psel_i     (dec_psel_i     ),
    .dec_penable_i  (dec_penable_i  ),
    .dec_pready_o   (dec_pready_o   ),
    .dec_paddr_i    (dec_paddr_i    ),
    .dec_pwrite_i   (dec_pwrite_i   ),
    .dec_pwdata_i   (dec_pwdata_i   ),
    .dec_pstrb_i    (dec_pstrb_i    ),
    .dec_prdata_o   (dec_prdata_o   ),

    .user_irq_i     (user_irq_i     ),

    .arvalid_o      (arvalid_pkd    ),
    .arready_i      (arready_pkd    ),
    .araddr_o       (araddr         ),
    .arlen_o        (arlen          ),
    .arid_o         (arid           ),
    .arburst_o      (arburst        ),
    .arsize_o       (arsize         ),

    .rvalid_i       (rvalid_pkd     ),
    .rready_o       (rready_pkd     ),
    .rdata_i        (rdata          ),
    .rlast_i        (rlast_pkd      ),
    .rresp_i        (rresp          ),
    .rid_i          (rid            ),

    .awvalid_o      (awvalid_pkd    ),
    .awready_i      (awready_pkd    ),
    .awaddr_o       (awaddr         ),
    .awlen_o        (awlen          ),
    .awid_o         (awid           ),
    .awburst_o      (awburst        ),
    .awsize_o       (awsize         ),

    .wvalid_o       (wvalid_pkd     ),
    .wready_i       (wready_pkd     ),
    .wdata_o        (wdata          ),
    .wlast_o        (wlast_pkd      ),
    .wstrb_o        (wstrb          ),

    .bvalid_i       (bvalid_pkd     ),
    .bready_o       (bready_pkd     ),
    .bid_i          (bid            ),
    .bresp_i        (bresp          ),

    .msix_awvalid_o (msix_awvalid   ),
    .msix_awready_i (msix_awready   ),
    .msix_awaddr_o  (msix_awaddr    ),
    .msix_awlen_o   (msix_awlen     ),
    .msix_awid_o    (msix_awid      ),
    .msix_awburst_o (msix_awburst   ),
    .msix_awsize_o  (msix_awsize    ),

    .msix_wvalid_o  (msix_wvalid    ),
    .msix_wready_i  (msix_wready    ),
    .msix_wdata_o   (msix_wdata     ),
    .msix_wlast_o   (msix_wlast     ),
    .msix_wstrb_o   (msix_wstrb     ),

    .msix_bvalid_i  (msix_bvalid    ),
    .msix_bready_o  (msix_bready    ),
    .msix_bid_i     (msix_bid       ),
    .msix_bresp_i   (msix_bresp     )
);

logic arvalid [DMA_CHANNEL_COUNT];
logic arready [DMA_CHANNEL_COUNT];
logic rvalid  [DMA_CHANNEL_COUNT];
logic rready  [DMA_CHANNEL_COUNT];
logic rlast   [DMA_CHANNEL_COUNT];
logic awvalid [DMA_CHANNEL_COUNT];
logic awready [DMA_CHANNEL_COUNT];
logic wvalid  [DMA_CHANNEL_COUNT];
logic wready  [DMA_CHANNEL_COUNT];
logic wlast   [DMA_CHANNEL_COUNT];
logic bvalid  [DMA_CHANNEL_COUNT];
logic bready  [DMA_CHANNEL_COUNT];

generate
    for (genvar i = 0; i < DMA_CHANNEL_COUNT; i++) begin : repacking
        assign arvalid[i] = arvalid_pkd[i];
        assign rready [i] = rready_pkd [i];
        assign awvalid[i] = awvalid_pkd[i];
        assign wvalid [i] = wvalid_pkd [i];
        assign wlast  [i] = wlast_pkd  [i];
        assign bready [i] = bready_pkd [i];

        assign awready_pkd[i] = awready[i];
        assign arready_pkd[i] = arready[i];
        assign rvalid_pkd [i] = rvalid [i];
        assign rlast_pkd  [i] = rlast  [i];
        assign wready_pkd [i] = wready [i];
        assign bvalid_pkd [i] = bvalid [i];
    end

    for (genvar i = 0; i < DMA_CHANNEL_COUNT; i++) begin : grouping
        logic                    regroup_arvalid;
        logic                    regroup_arready;
        logic [63:0]             regroup_araddr ;
        logic [7:0]              regroup_arlen  ;
        logic [AXI_ID_WIDTH-1:0] regroup_arid   ;
        logic [1:0]              regroup_arburst;
        logic [2:0]              regroup_arsize ;

        logic                    regroup_rvalid ;
        logic                    regroup_rready ;
        logic [127:0]            regroup_rdata  ;
        logic                    regroup_rlast  ;
        logic [1:0]              regroup_rresp  ;
        logic [AXI_ID_WIDTH-1:0] regroup_rid    ;

        logic                    regroup_awvalid;
        logic                    regroup_awready;
        logic [63:0]             regroup_awaddr ;
        logic [7:0]              regroup_awlen  ;
        logic [AXI_ID_WIDTH-1:0] regroup_awid   ;
        logic [1:0]              regroup_awburst;
        logic [2:0]              regroup_awsize ;

        logic                    regroup_wvalid ;
        logic                    regroup_wready ;
        logic [127:0]            regroup_wdata  ;
        logic                    regroup_wlast  ;
        logic [15:0]             regroup_wstrb  ;

        logic                    regroup_bvalid ;
        logic                    regroup_bready ;
        logic [AXI_ID_WIDTH-1:0] regroup_bid    ;
        logic [1:0]              regroup_bresp  ;

        assign regroup_arvalid = arvalid[i];
        assign regroup_arready = arready[i];
        assign regroup_araddr  = araddr [i];
        assign regroup_arlen   = arlen  [i];
        assign regroup_arid    = arid   [i];
        assign regroup_arburst = arburst[i];
        assign regroup_arsize  = arsize [i];
        assign regroup_rvalid  = rvalid [i];
        assign regroup_rready  = rready [i];
        assign regroup_rdata   = rdata  [i];
        assign regroup_rlast   = rlast  [i];
        assign regroup_rresp   = rresp  [i];
        assign regroup_rid     = rid    [i];
        assign regroup_awvalid = awvalid[i];
        assign regroup_awready = awready[i];
        assign regroup_awaddr  = awaddr [i];
        assign regroup_awlen   = awlen  [i];
        assign regroup_awid    = awid   [i];
        assign regroup_awburst = awburst[i];
        assign regroup_awsize  = awsize [i];
        assign regroup_wvalid  = wvalid [i];
        assign regroup_wready  = wready [i];
        assign regroup_wdata   = wdata  [i];
        assign regroup_wlast   = wlast  [i];
        assign regroup_wstrb   = wstrb  [i];
        assign regroup_bvalid  = bvalid [i];
        assign regroup_bready  = bready [i];
        assign regroup_bid     = bid    [i];
        assign regroup_bresp   = bresp  [i];
    end
endgenerate


task automatic csr_access(
    input  logic         write ,
    input  logic [63:0]  addr  ,
    input  logic [127:0] wdata ,
    input  logic [15:0]  strobe,
    output logic [127:0] rdata 
);
    csr_psel_i    = '1    ;
    csr_penable_i = '0    ;
    csr_paddr_i   = addr  ;
    csr_pwrite_i  = write ;
    csr_pwdata_i  = wdata ;
    csr_pstrb_i   = strobe;

    @(posedge clk);
    csr_penable_i = '1;

    @(posedge clk);
    while (!csr_pready_o) begin
        @(posedge clk);
    end
    csr_psel_i    = '0;
    csr_penable_i = '0;

    rdata = csr_prdata_o;
endtask

task automatic msix_access(
    input  logic         write ,
    input  logic [63:0]  addr  ,
    input  logic [127:0] wdata ,
    input  logic [15:0]  strobe,
    output logic [127:0] rdata 
);
    msix_psel_i    = '1    ;
    msix_penable_i = '0    ;
    msix_paddr_i   = addr  ;
    msix_pwrite_i  = write ;
    msix_pwdata_i  = wdata ;
    msix_pstrb_i   = strobe;

    @(posedge clk);
    msix_penable_i = '1;

    @(posedge clk);
    while (!msix_pready_o) begin
        @(posedge clk);
    end
    msix_psel_i    = '0;
    msix_penable_i = '0;

    rdata = msix_prdata_o;
endtask

task automatic dec_access(
    input  logic         write ,
    input  logic [63:0]  addr  ,
    input  logic [127:0] wdata ,
    input  logic [15:0]  strobe,
    output logic [127:0] rdata 
);
    dec_psel_i    = '1    ;
    dec_penable_i = '0    ;
    dec_paddr_i   = addr  ;
    dec_pwrite_i  = write ;
    dec_pwdata_i  = wdata ;
    dec_pstrb_i   = strobe;

    @(posedge clk);
    dec_penable_i = '1;

    @(posedge clk);
    while (!dec_pready_o) begin
        @(posedge clk);
    end
    dec_psel_i    = '0;
    dec_penable_i = '0;

    rdata = dec_prdata_o;
endtask

always #4 clk = ~clk;

logic test_done, check_mem;
logic [127:0] apb_rdata, devnull, curr_addr;

logic [21:0] offsets    [DMA_CHANNEL_COUNT];
logic [21:0] bytecounts [DMA_CHANNEL_COUNT];

initial begin
    test_done = 0;
    check_mem = 0;

    clk = 1;
    #2;
    rst_n = 0;

    csr_psel_i     = '0;
    csr_penable_i  = '0;
    
    msix_psel_i    = '0;
    msix_penable_i = '0;
    
    dec_psel_i     = '0;
    dec_penable_i  = '0;
    
    user_irq_i     = '0;

    @(posedge clk);
    @(posedge clk);
    rst_n = 1;

    csr_access (
        .write  ('1),
        .addr   ('0),
        .wdata  (1 << 96),
        .strobe (16'hF000),
        .rdata  (devnull)
    );

    @(posedge clk);
    for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) begin
        msix_access (
            .write  ('1),
            .addr   (i * 'h10),
            .wdata  ({32'h0, 32'($urandom()), 64'(i*'h4)}),
            .strobe (16'hFFFF),
            .rdata  (devnull)
        );
    end

    @(posedge clk);
    csr_access (
        .write  ('0),
        .addr   ('0),
        .wdata  ('0),
        .strobe (16'hFFFF),
        .rdata  (apb_rdata)
    );
    apb_rdata = apb_rdata[31:16];

    for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
        csr_access (
            .write  ('1),
            .addr   (apb_rdata),
            .wdata  ((48'hF000_0000_0000 + i * 'h4) << 32),
            .strobe (16'h0FF0),
            .rdata  (devnull)
        );
        csr_access (
            .write  ('0),
            .addr   (apb_rdata),
            .wdata  ('0),
            .strobe (16'hFFFF),
            .rdata  (apb_rdata)
        );
        apb_rdata = apb_rdata[31:0];
    end

    for (int iter = 0; iter < 2; iter++) begin
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            logic [31:0] offset, bytecount;
            bytecount = $urandom_range(1, 64) * 16;
            offset = $urandom_range(0, 128) * 16;

            bytecounts[i] = bytecount;
            offsets   [i] = offset   ;

            dec_access (
                .write  ('1),
                .addr   (i * 'h10),
                .wdata  ({bytecount, offset} << 64),
                .strobe (16'hFF00),
                .rdata  (devnull)
            );
            dec_access (
                .write  ('1),
                .addr   (i * 'h10),
                .wdata  ({bytecount, offset + 1024}),
                .strobe (16'h00FF),
                .rdata  (devnull)
            );
        end

        csr_access (
            .write  ('0),
            .addr   ('0),
            .wdata  ('0),
            .strobe (16'hFFFF),
            .rdata  (curr_addr)
        );
        curr_addr = curr_addr[31:16];

        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            apb_rdata = '0;
            while (apb_rdata != 'b1100) begin
                csr_access (
                    .write  ('0),
                    .addr   (curr_addr + 'h20),
                    .wdata  ('0),
                    .strobe (16'hFFFF),
                    .rdata  (apb_rdata)
                );
            end
            csr_access (
                .write  ('0),
                .addr   (curr_addr),
                .wdata  ('0),
                .strobe (16'hFFFF),
                .rdata  (curr_addr)
            );
            curr_addr = curr_addr[31:0];
        end

        csr_access (
            .write  ('0),
            .addr   ('0),
            .wdata  ('0),
            .strobe (16'hFFFF),
            .rdata  (curr_addr)
        );
        curr_addr = curr_addr[31:16];
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            csr_access (
                .write  ('1),
                .addr   (curr_addr + 'h20),
                .wdata  ('b11),
                .strobe (16'h000F),
                .rdata  (devnull)
            );
            csr_access (
                .write  ('0),
                .addr   (curr_addr),
                .wdata  ('1),
                .strobe (16'hFFFF),
                .rdata  (curr_addr)
            );
            curr_addr = curr_addr[31:0];
        end

        check_mem = 1;
        @(negedge check_mem);
    end

    test_done = 1;
end

endmodule