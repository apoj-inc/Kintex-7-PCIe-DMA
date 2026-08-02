module kdma_echodevice_bridged #(
    parameter     BAR_COUNT                             = 4         ,

    parameter     DMA_CHANNEL_COUNT                     = 2         ,
    parameter     PIPELINE_CAPACITY                     = 4         ,

    parameter     DMA_BYTES_WIDTH                       = 22        ,
    parameter     DMA_OFFFSET_WIDTH                     = 22        ,

    parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{2{16  }},
    parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{16  }},
    parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{16  }},
    parameter     DMA_TQ_DEPTH                          = 2         ,

    parameter     MAX_WQ_DEPTH                          = 16        ,
    parameter     MAX_RQ_DEPTH                          = 16        ,

    parameter AXI_ID_WIDTH   = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY),
    parameter MSIX_COUNT     = DMA_CHANNEL_COUNT                                     
) (
    input  logic                  clk              ,
    input  logic                  rst_n            ,

    input  logic                  pcie_valid_i     ,
    output logic                  pcie_ready_o     ,
    input  logic [127:0]          pcie_data_i      ,
    input  logic [4:0]            pcie_sof_i       ,
    input  logic [4:0]            pcie_eof_i       ,
    input  logic [7:0]            pcie_bar_hit_i   ,

    output logic                  pcie_valid_o     ,
    input  logic                  pcie_ready_i     ,
    output logic [127:0]          pcie_data_o      ,
    output logic [15:0]           pcie_tkeep_o     ,
    output logic                  pcie_tlast_o     ,

    input  logic [7:0]            bus_number_i     ,
    input  logic [4:0]            device_number_i  ,
    input  logic [2:0]            function_number_i,

    input  logic [MSIX_COUNT-1:0] user_irq_i       
);

logic [BAR_COUNT-1:0]         bar_psel                           ;
logic                         bar_penable                        ;
logic [BAR_COUNT-1:0]         bar_pready                         ;
logic [63:0]                  bar_paddr                          ;
logic                         bar_pwrite                         ;
logic [127:0]                 bar_pwdata                         ;
logic [15:0]                  bar_pstrb                          ;
logic [127:0]                 bar_prdata      [BAR_COUNT]        ;

logic [DMA_CHANNEL_COUNT-1:0] arvalid                            ;
logic [DMA_CHANNEL_COUNT-1:0] arready                            ;
logic [63:0]                  araddr          [DMA_CHANNEL_COUNT];
logic [7:0]                   arlen           [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      arid            [DMA_CHANNEL_COUNT];
logic [1:0]                   arburst         [DMA_CHANNEL_COUNT];
logic [2:0]                   arsize          [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] rvalid                             ;
logic [DMA_CHANNEL_COUNT-1:0] rready                             ;
logic [127:0]                 rdata           [DMA_CHANNEL_COUNT];
logic [DMA_CHANNEL_COUNT-1:0] rlast                              ;
logic [1:0]                   rresp           [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      rid             [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] awvalid                            ;
logic [DMA_CHANNEL_COUNT-1:0] awready                            ;
logic [63:0]                  awaddr          [DMA_CHANNEL_COUNT];
logic [7:0]                   awlen           [DMA_CHANNEL_COUNT];
logic [AXI_ID_WIDTH-1:0]      awid            [DMA_CHANNEL_COUNT];
logic [1:0]                   awburst         [DMA_CHANNEL_COUNT];
logic [2:0]                   awsize          [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] wvalid                             ;
logic [DMA_CHANNEL_COUNT-1:0] wready                             ;
logic [127:0]                 wdata           [DMA_CHANNEL_COUNT];
logic [DMA_CHANNEL_COUNT-1:0] wlast                              ;
logic [15:0]                  wstrb           [DMA_CHANNEL_COUNT];

logic [DMA_CHANNEL_COUNT-1:0] bvalid                             ;
logic [DMA_CHANNEL_COUNT-1:0] bready                             ;
logic [AXI_ID_WIDTH-1:0]      bid             [DMA_CHANNEL_COUNT];
logic [1:0]                   bresp           [DMA_CHANNEL_COUNT];

logic                         msix_awvalid                       ;
logic                         msix_awready                       ;
logic [63:0]                  msix_awaddr                        ;
logic [7:0]                   msix_awlen                         ;
logic [AXI_ID_WIDTH-1:0]      msix_awid                          ;
logic [1:0]                   msix_awburst                       ;
logic [2:0]                   msix_awsize                        ;

logic                         msix_wvalid                        ;
logic                         msix_wready                        ;
logic [127:0]                 msix_wdata                         ;
logic                         msix_wlast                         ;
logic [15:0]                  msix_wstrb                         ;

logic                         msix_bvalid                        ;
logic                         msix_bready                        ;
logic [AXI_ID_WIDTH-1:0]      msix_bid                           ;
logic [1:0]                   msix_bresp                         ;


kdma_pcie_axi_bridge #(
    .BAR_COUNT         (BAR_COUNT        ),

    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
    .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
) u_kdma_pcie_axi_bridge (
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

    .bar_psel_o        (bar_psel         ),
    .bar_penable_o     (bar_penable      ),
    .bar_pready_i      (bar_pready       ),
    .bar_paddr_o       (bar_paddr        ),
    .bar_pwrite_o      (bar_pwrite       ),
    .bar_pwdata_o      (bar_pwdata       ),
    .bar_pstrb_o       (bar_pstrb        ),
    .bar_prdata_i      (bar_prdata       ),

    .arvalid_i         (arvalid          ),
    .arready_o         (arready          ),
    .araddr_i          (araddr           ),
    .arlen_i           (arlen            ),
    .arid_i            (arid             ),
    .arburst_i         (arburst          ),
    .arsize_i          (arsize           ),

    .rvalid_o          (rvalid           ),
    .rready_i          (rready           ),
    .rdata_o           (rdata            ),
    .rlast_o           (rlast            ),
    .rresp_o           (rresp            ),
    .rid_o             (rid              ),

    .awvalid_i         (awvalid          ),
    .awready_o         (awready          ),
    .awaddr_i          (awaddr           ),
    .awlen_i           (awlen            ),
    .awid_i            (awid             ),
    .awburst_i         (awburst          ),
    .awsize_i          (awsize           ),

    .wvalid_i          (wvalid           ),
    .wready_o          (wready           ),
    .wdata_i           (wdata            ),
    .wlast_i           (wlast            ),
    .wstrb_i           (wstrb            ),

    .bvalid_o          (bvalid           ),
    .bready_i          (bready           ),
    .bid_o             (bid              ),
    .bresp_o           (bresp            ),

    .msix_awvalid_i    (msix_awvalid     ),
    .msix_awready_o    (msix_awready     ),
    .msix_awaddr_i     (msix_awaddr      ),
    .msix_awlen_i      (msix_awlen       ),
    .msix_awid_i       (msix_awid        ),
    .msix_awburst_i    (msix_awburst     ),
    .msix_awsize_i     (msix_awsize      ),

    .msix_wvalid_i     (msix_wvalid      ),
    .msix_wready_o     (msix_wready      ),
    .msix_wdata_i      (msix_wdata       ),
    .msix_wlast_i      (msix_wlast       ),
    .msix_wstrb_i      (msix_wstrb       ),

    .msix_bvalid_o     (msix_bvalid      ),
    .msix_bready_i     (msix_bready      ),
    .msix_bid_o        (msix_bid         ),
    .msix_bresp_o      (msix_bresp       ),

    .bus_number_i      (bus_number_i     ),
    .device_number_i   (device_number_i  ),
    .function_number_i (function_number_i)

);

logic         csr_psel   ;
logic         csr_penable;
logic         csr_pready ;
logic [63:0]  csr_paddr  ;
logic         csr_pwrite ;
logic [127:0] csr_pwdata ;
logic [15:0]  csr_pstrb  ;
logic [127:0] csr_prdata ;

logic         dec_psel   ;
logic         dec_penable;
logic         dec_pready ;
logic [63:0]  dec_paddr  ;
logic         dec_pwrite ;
logic [127:0] dec_pwdata ;
logic [15:0]  dec_pstrb  ;
logic [127:0] dec_prdata ;

always_comb begin
    csr_psel    = '0;
    csr_penable = bar_penable;
    csr_paddr   = bar_paddr  ;
    csr_pwrite  = bar_pwrite ;
    csr_pwdata  = bar_pwdata ;
    csr_pstrb   = bar_pstrb  ;

    dec_psel    = '0;
    dec_penable = bar_penable;
    dec_paddr   = bar_paddr  ;
    dec_pwrite  = bar_pwrite ;
    dec_pwdata  = bar_pwdata ;
    dec_pstrb   = bar_pstrb  ;

    bar_pready[2] = '0;
    bar_prdata[2] = '0;

    if (bar_paddr[2] < 'h1000) begin
        csr_psel = bar_psel[2];

        bar_pready[2] = csr_pready;
        bar_prdata[2] = csr_prdata;
    end
    else begin
        dec_psel = bar_psel[2];

        bar_pready[2] = dec_pready;
        bar_prdata[2] = dec_prdata;
    end

    bar_pready[1] = '0;
    bar_prdata[1] = '0;

    bar_pready[3] = '0;
    bar_prdata[3] = '0;
end

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
) u_kdma_echodevice (
    .clk            (clk            ),
    .rst_n          (rst_n          ),

    .csr_psel_i     (csr_psel       ),
    .csr_penable_i  (csr_penable    ),
    .csr_pready_o   (csr_pready     ),
    .csr_paddr_i    (csr_paddr      ),
    .csr_pwrite_i   (csr_pwrite     ),
    .csr_pwdata_i   (csr_pwdata     ),
    .csr_pstrb_i    (csr_pstrb      ),
    .csr_prdata_o   (csr_prdata     ),

    .msix_psel_i    (bar_psel    [0]),
    .msix_penable_i (bar_penable    ),
    .msix_pready_o  (bar_pready  [0]),
    .msix_paddr_i   (bar_paddr      ),
    .msix_pwrite_i  (bar_pwrite     ),
    .msix_pwdata_i  (bar_pwdata     ),
    .msix_pstrb_i   (bar_pstrb      ),
    .msix_prdata_o  (bar_prdata  [0]),

    .dec_psel_i     (dec_psel       ),
    .dec_penable_i  (dec_penable    ),
    .dec_pready_o   (dec_pready     ),
    .dec_paddr_i    (dec_paddr      ),
    .dec_pwrite_i   (dec_pwrite     ),
    .dec_pwdata_i   (dec_pwdata     ),
    .dec_pstrb_i    (dec_pstrb      ),
    .dec_prdata_o   (dec_prdata     ),

    .user_irq_i     (user_irq_i     ),

    .arvalid_o      (arvalid        ),
    .arready_i      (arready        ),
    .araddr_o       (araddr         ),
    .arlen_o        (arlen          ),
    .arid_o         (arid           ),
    .arburst_o      (arburst        ),
    .arsize_o       (arsize         ),

    .rvalid_i       (rvalid         ),
    .rready_o       (rready         ),
    .rdata_i        (rdata          ),
    .rlast_i        (rlast          ),
    .rresp_i        (rresp          ),
    .rid_i          (rid            ),

    .awvalid_o      (awvalid        ),
    .awready_i      (awready        ),
    .awaddr_o       (awaddr         ),
    .awlen_o        (awlen          ),
    .awid_o         (awid           ),
    .awburst_o      (awburst        ),
    .awsize_o       (awsize         ),

    .wvalid_o       (wvalid         ),
    .wready_i       (wready         ),
    .wdata_o        (wdata          ),
    .wlast_o        (wlast          ),
    .wstrb_o        (wstrb          ),

    .bvalid_i       (bvalid         ),
    .bready_o       (bready         ),
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
    
endmodule