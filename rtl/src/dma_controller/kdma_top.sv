module kdma_top #(
    parameter     DMA_CHANNEL_COUNT                     = 8         ,
    parameter     PIPELINE_CAPACITY                     = 4         ,
    
    parameter     DMA_BYTES_WIDTH                       = 22        ,
    parameter     DMA_OFFFSET_WIDTH                     = 22        ,

    parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{8{16  }},
    parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{1024}},
    parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{1024}},
    parameter     DMA_TQ_DEPTH                          = 8         ,

    parameter     MAX_WQ_DEPTH                          = 1024      ,
    parameter     MAX_RQ_DEPTH                          = 1024      ,

    parameter MSIX_COUNT              = DMA_CHANNEL_COUNT                                     ,
    parameter AXI_ID_WIDTH            = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY),
    parameter DMA_WQ_ADDR_WIDTH       = $clog2(MAX_WQ_DEPTH)                                  ,
    parameter DMA_RQ_ADDR_WIDTH       = $clog2(MAX_RQ_DEPTH)                                  ,
    parameter DMA_TQ_ADDR_WIDTH       = $clog2(DMA_TQ_DEPTH)                                  ,
    parameter PBA_COUNT               = MSIX_COUNT / 64 + (MSIX_COUNT % 64 != 0)              ,
    parameter DMA_BURST_WIDTH         = DMA_BYTES_WIDTH - 4                                   ,
    parameter DMA_CHANNEL_COUNT_WIDTH = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT)
) (
    input  logic                         clk                                     ,
    input  logic                         rst_n                                   ,

    input  logic                         csr_psel_i                              ,
    input  logic                         csr_penable_i                           ,
    output logic                         csr_pready_o                            ,
    input  logic [63:0]                  csr_paddr_i                             ,
    input  logic                         csr_pwrite_i                            ,
    input  logic [127:0]                 csr_pwdata_i                            ,
    input  logic [15:0]                  csr_pstrb_i                             ,
    output logic [127:0]                 csr_prdata_o                            ,

    input  logic                         msix_psel_i                             ,
    input  logic                         msix_penable_i                          ,
    output logic                         msix_pready_o                           ,
    input  logic [63:0]                  msix_paddr_i                            ,
    input  logic                         msix_pwrite_i                           ,
    input  logic [127:0]                 msix_pwdata_i                           ,
    input  logic [15:0]                  msix_pstrb_i                            ,
    output logic [127:0]                 msix_prdata_o                           ,

    input  logic                         dec_psel_i                              ,
    input  logic                         dec_penable_i                           ,
    output logic                         dec_pready_o                            ,
    input  logic [63:0]                  dec_paddr_i                             ,
    input  logic                         dec_pwrite_i                            ,
    input  logic [127:0]                 dec_pwdata_i                            ,
    input  logic [15:0]                  dec_pstrb_i                             ,
    output logic [127:0]                 dec_prdata_o                            ,

    input  logic [MSIX_COUNT-1:0]        user_irq_i                              ,

    output logic [DMA_CHANNEL_COUNT-1:0] arvalid_o                               ,
    input  logic [DMA_CHANNEL_COUNT-1:0] arready_i                               ,
    output logic [63:0]                  araddr_o             [DMA_CHANNEL_COUNT],
    output logic [7:0]                   arlen_o              [DMA_CHANNEL_COUNT],
    output logic [AXI_ID_WIDTH-1:0]      arid_o               [DMA_CHANNEL_COUNT],
    output logic [1:0]                   arburst_o            [DMA_CHANNEL_COUNT],
    output logic [2:0]                   arsize_o             [DMA_CHANNEL_COUNT],

    input  logic [DMA_CHANNEL_COUNT-1:0] rvalid_i                                ,
    output logic [DMA_CHANNEL_COUNT-1:0] rready_o                                ,
    input  logic [127:0]                 rdata_i              [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0] rlast_i                                 ,
    input  logic [1:0]                   rresp_i              [DMA_CHANNEL_COUNT],
    input  logic [AXI_ID_WIDTH-1:0]      rid_i                [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] awvalid_o                               ,
    input  logic [DMA_CHANNEL_COUNT-1:0] awready_i                               ,
    output logic [63:0]                  awaddr_o             [DMA_CHANNEL_COUNT],
    output logic [7:0]                   awlen_o              [DMA_CHANNEL_COUNT],
    output logic [AXI_ID_WIDTH-1:0]      awid_o               [DMA_CHANNEL_COUNT],
    output logic [1:0]                   awburst_o            [DMA_CHANNEL_COUNT],
    output logic [2:0]                   awsize_o             [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] wvalid_o                                ,
    input  logic [DMA_CHANNEL_COUNT-1:0] wready_i                                ,
    output logic [127:0]                 wdata_o              [DMA_CHANNEL_COUNT],
    output logic [DMA_CHANNEL_COUNT-1:0] wlast_o                                 ,
    output logic [15:0]                  wstrb_o              [DMA_CHANNEL_COUNT],

    input  logic [DMA_CHANNEL_COUNT-1:0] bvalid_i                                ,
    output logic [DMA_CHANNEL_COUNT-1:0] bready_o                                ,
    input  logic [AXI_ID_WIDTH-1:0]      bid_i                [DMA_CHANNEL_COUNT],
    input  logic [1:0]                   bresp_i              [DMA_CHANNEL_COUNT],

    output logic                         msix_awvalid_o                          ,
    input  logic                         msix_awready_i                          ,
    output logic [63:0]                  msix_awaddr_o                           ,
    output logic [7:0]                   msix_awlen_o                            ,
    output logic [AXI_ID_WIDTH-1:0]      msix_awid_o                             ,
    output logic [1:0]                   msix_awburst_o                          ,
    output logic [2:0]                   msix_awsize_o                           ,

    output logic                         msix_wvalid_o                           ,
    input  logic                         msix_wready_i                           ,
    output logic [127:0]                 msix_wdata_o                            ,
    output logic                         msix_wlast_o                            ,
    output logic [15:0]                  msix_wstrb_o                            ,

    input  logic                         msix_bvalid_i                           ,
    output logic                         msix_bready_o                           ,
    input  logic [AXI_ID_WIDTH-1:0]      msix_bid_i                              ,
    input  logic [1:0]                   msix_bresp_i                            ,

    input  logic                         dma_wrdata_valid_i   [DMA_CHANNEL_COUNT],
    output logic                         dma_wrdata_ready_o   [DMA_CHANNEL_COUNT],
    input  logic [DMA_WQ_ADDR_WIDTH:0]   dma_wrdata_count_i   [DMA_CHANNEL_COUNT],
    input  logic [127:0]                 dma_wrdata_data_i    [DMA_CHANNEL_COUNT],

    output logic                         dma_rddata_valid_o   [DMA_CHANNEL_COUNT],
    input  logic                         dma_rddata_ready_i   [DMA_CHANNEL_COUNT],
    input  logic [DMA_RQ_ADDR_WIDTH:0]   dma_rddata_free_i    [DMA_CHANNEL_COUNT],
    output logic [127:0]                 dma_rddata_data_o    [DMA_CHANNEL_COUNT],

    output logic                         dma_resetn_o                            
);

    logic dma_resetn;

    logic [63:0] dma_addr [DMA_CHANNEL_COUNT];

    logic [31:0] dma_msix_mask  [MSIX_COUNT];
    logic [31:0] dma_msix_data  [MSIX_COUNT];
    logic [63:0] dma_msix_addrs [MSIX_COUNT];
    
    logic [31:0] user_msix_mask  [MSIX_COUNT];
    logic [31:0] user_msix_data  [MSIX_COUNT];
    logic [63:0] user_msix_addrs [MSIX_COUNT];
    
    logic [31:0] msix_mask  [MSIX_COUNT*3];
    logic [31:0] msix_data  [MSIX_COUNT*3];
    logic [63:0] msix_addrs [MSIX_COUNT*3];

    logic [21:0]                  bytecount_wr    [DMA_CHANNEL_COUNT];
    logic [21:0]                  offset_wr       [DMA_CHANNEL_COUNT];
    logic [21:0]                  bytecount_rd    [DMA_CHANNEL_COUNT];
    logic [21:0]                  offset_rd       [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] btcnt_wr_swmod                     ;
    logic [DMA_CHANNEL_COUNT-1:0] ofst_wr_swmod                      ;
    logic [DMA_CHANNEL_COUNT-1:0] btcnt_rd_swmod                     ;
    logic [DMA_CHANNEL_COUNT-1:0] ofst_rd_swmod                      ;

    logic                               dma_task_valid_wr  ;
    logic                               dma_task_ready_wr  ;
    logic [DMA_CHANNEL_COUNT_WIDTH-1:0] dma_task_channel_wr;
    logic [DMA_BURST_WIDTH-1:0]         dma_task_burst_wr  ;
    logic [DMA_OFFFSET_WIDTH-1:0]       dma_task_offset_wr ;
    logic                               dma_task_write_wr  ;

    logic [DMA_CHANNEL_COUNT-1:0] dmard_task_valid                     ;
    logic [DMA_CHANNEL_COUNT-1:0] dmard_task_ready                     ;
    logic [DMA_BURST_WIDTH-1:0]   dmard_task_burst  [DMA_CHANNEL_COUNT];
    logic [DMA_OFFFSET_WIDTH-1:0] dmard_task_offset [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] dmard_task_write                     ;
    logic [5:0]                   dmard_task_init   [DMA_CHANNEL_COUNT];

    logic [DMA_CHANNEL_COUNT-1:0] dmawr_task_valid                     ;
    logic [DMA_CHANNEL_COUNT-1:0] dmawr_task_ready                     ;
    logic [DMA_BURST_WIDTH-1:0]   dmawr_task_burst  [DMA_CHANNEL_COUNT];
    logic [DMA_OFFFSET_WIDTH-1:0] dmawr_task_offset [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] dmawr_task_write                     ;
    logic [5:0]                   dmawr_task_init   [DMA_CHANNEL_COUNT];

    logic [DMA_TQ_ADDR_WIDTH:0] dmard_task_free, dmawr_task_free;

    logic [MSIX_COUNT*3-1:0] irq_wires;
    logic [MSIX_COUNT-1:0]   dma_rd_irq_sts, dma_wr_irq_sts;
    logic [MSIX_COUNT-1:0]   dma_rd_irq_clr, dma_wr_irq_clr;

    assign dma_resetn_o = dma_resetn;
    assign irq_wires = {user_irq_i, dma_rd_irq_sts, dma_wr_irq_sts};

    kdma_csr_flatten #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),

        .DMA_WQ_DEPTH      (DMA_WQ_DEPTH     ),
        .DMA_RQ_DEPTH      (DMA_RQ_DEPTH     ),
        .DMA_TQ_DEPTH      (DMA_TQ_DEPTH     ),

        .MAX_WQ_DEPTH      (MAX_WQ_DEPTH     ),
        .MAX_RQ_DEPTH      (MAX_RQ_DEPTH     )
    ) u_kdma_csr_flatten (
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .bar_psel_i         (csr_psel_i         ),
        .bar_penable_i      (csr_penable_i      ),
        .bar_pready_o       (csr_pready_o       ),
        .bar_paddr_i        (csr_paddr_i        ),
        .bar_pwrite_i       (csr_pwrite_i       ),
        .bar_pwdata_i       (csr_pwdata_i       ),
        .bar_pstrb_i        (csr_pstrb_i        ),
        .bar_prdata_o       (csr_prdata_o       ),

        .dma_reset_o        (dma_resetn         ),
        .dmawr_irq_clr_o    (dma_wr_irq_clr     ),
        .dmard_irq_clr_o    (dma_rd_irq_clr     ),
        .dma_addr_o         (dma_addr           ),

        .dmawr_task_free_i  (dmawr_task_free    ),
        .dmard_task_free_i  (dmard_task_free    ),
        .dmawr_data_count_i (dma_wrdata_count_i ),
        .dmard_data_free_i  (dma_rddata_free_i  ),
        .dmawr_irq_sts_i    (dma_wr_irq_sts     ),
        .dmard_irq_sts_i    (dma_rd_irq_sts     )
    );

    kdma_msix_flatten #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_msix_flatten (
        .clk               (clk             ),
        .rst_n             (rst_n           ),

        .bar_psel_i        (msix_psel_i     ),
        .bar_penable_i     (msix_penable_i  ),
        .bar_pready_o      (msix_pready_o   ),
        .bar_paddr_i       (msix_paddr_i    ),
        .bar_pwrite_i      (msix_pwrite_i   ),
        .bar_pwdata_i      (msix_pwdata_i   ),
        .bar_pstrb_i       (msix_pstrb_i    ),
        .bar_prdata_o      (msix_prdata_o   ),

        .dma_msix_mask_o   (dma_msix_mask   ),
        .dma_msix_data_o   (dma_msix_data   ),
        .dma_msix_addrs_o  (dma_msix_addrs  ),

        .user_msix_mask_o  (user_msix_mask  ),
        .user_msix_data_o  (user_msix_data  ),
        .user_msix_addrs_o (user_msix_addrs )
    );

    kdma_decoder_flatten #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_decoder_flatten (
        .clk              (clk           ),
        .rst_n            (rst_n         ),

        .bar_psel_i       (dec_psel_i    ),
        .bar_penable_i    (dec_penable_i ),
        .bar_pready_o     (dec_pready_o  ),
        .bar_paddr_i      (dec_paddr_i   ),
        .bar_pwrite_i     (dec_pwrite_i  ),
        .bar_pwdata_i     (dec_pwdata_i  ),
        .bar_pstrb_i      (dec_pstrb_i   ),
        .bar_prdata_o     (dec_prdata_o  ),

        .bytecount_wr_o   (bytecount_wr  ),
        .offset_wr_o      (offset_wr     ),
        .bytecount_rd_o   (bytecount_rd  ),
        .offset_rd_o      (offset_rd     ),

        .btcnt_wr_swmod_o (btcnt_wr_swmod),
        .ofst_wr_swmod_o  (ofst_wr_swmod ),
        .btcnt_rd_swmod_o (btcnt_rd_swmod),
        .ofst_rd_swmod_o  (ofst_rd_swmod )
    );

    kdma_decoder #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
        .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH),
        .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH  )
    ) u_kdma_decoder (
        .clk                (clk                ),
        .rst_n              (dma_resetn         ),

        .bytecount_wr_i     (bytecount_wr       ),
        .offset_wr_i        (offset_wr          ),
        .bytecount_rd_i     (bytecount_rd       ),
        .offset_rd_i        (offset_rd          ),
        .btcnt_wr_swmod_i   (btcnt_wr_swmod     ),
        .ofst_wr_swmod_i    (ofst_wr_swmod      ),
        .btcnt_rd_swmod_i   (btcnt_rd_swmod     ),
        .ofst_rd_swmod_i    (ofst_rd_swmod      ),

        .dma_task_valid_o   (dma_task_valid_wr  ),
        .dma_task_ready_i   (dma_task_ready_wr  ),
        .dma_task_channel_o (dma_task_channel_wr),
        .dma_task_burst_o   (dma_task_burst_wr  ),
        .dma_task_offset_o  (dma_task_offset_wr ),
        .dma_task_write_o   (dma_task_write_wr  )
    );

    kdma_task_transport #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),

        .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH  ),
        .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH),

        .DMA_WQ_DEPTH      (DMA_WQ_DEPTH     ),
        .DMA_RQ_DEPTH      (DMA_RQ_DEPTH     ),
        .DMA_TQ_DEPTH      (DMA_TQ_DEPTH     )
    ) u_kdma_task_transport (
        .clk                 (clk                ),
        .rst_n               (dma_resetn         ),

        .dma_task_valid_i    (dma_task_valid_wr  ),
        .dma_task_ready_o    (dma_task_ready_wr  ),
        .dma_task_channel_i  (dma_task_channel_wr),
        .dma_task_burst_i    (dma_task_burst_wr  ),
        .dma_task_offset_i   (dma_task_offset_wr ),
        .dma_task_write_i    (dma_task_write_wr  ),

        .dmawr_task_free_o   (dmawr_task_free    ),
        .dmard_task_free_o   (dmard_task_free    ),

        .dmawr_task_valid_o  (dmawr_task_valid   ),
        .dmawr_task_ready_i  (dmawr_task_ready   ),
        .dmawr_task_burst_o  (dmawr_task_burst   ),
        .dmawr_task_offset_o (dmawr_task_offset  ),
        .dmawr_task_write_o  (dmawr_task_write   ),
        .dmawr_task_init_o   (dmawr_task_init    ),

        .dmard_task_valid_o  (dmard_task_valid   ),
        .dmard_task_ready_i  (dmard_task_ready   ),
        .dmard_task_burst_o  (dmard_task_burst   ),
        .dmard_task_offset_o (dmard_task_offset  ),
        .dmard_task_write_o  (dmard_task_write   ),
        .dmard_task_init_o   (dmard_task_init    )
    );

    kdma_dmic #(
        .MSIX_COUNT        (MSIX_COUNT*3     ),
        .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
    ) u_kdma_dmic (
        .clk            (clk           ),
        .rst_n          (dma_resetn    ),

        .irq_i          (irq_wires     ),

        .msix_mask_i    (msix_mask     ),
        .msix_data_i    (msix_data     ),
        .msix_addrs_i   (msix_addrs    ),

        .msix_awvalid_o (msix_awvalid_o),
        .msix_awready_i (msix_awready_i),
        .msix_awaddr_o  (msix_awaddr_o ),
        .msix_awlen_o   (msix_awlen_o  ),
        .msix_awid_o    (msix_awid_o   ),
        .msix_awburst_o (msix_awburst_o),
        .msix_awsize_o  (msix_awsize_o ),

        .msix_wvalid_o  (msix_wvalid_o ),
        .msix_wready_i  (msix_wready_i ),
        .msix_wdata_o   (msix_wdata_o  ),
        .msix_wlast_o   (msix_wlast_o  ),
        .msix_wstrb_o   (msix_wstrb_o  ),

        .msix_bvalid_i  (msix_bvalid_i ),
        .msix_bready_o  (msix_bready_o ),
        .msix_bid_i     (msix_bid_i    ),
        .msix_bresp_i   (msix_bresp_i  )
    );

    generate
        genvar i;

        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : dma_channels
            assign msix_mask [i] = dma_msix_mask [i];
            assign msix_data [i] = dma_msix_data [i];
            assign msix_addrs[i] = dma_msix_addrs[i];
            
            assign msix_mask [i + DMA_CHANNEL_COUNT] = dma_msix_mask [i];
            assign msix_data [i + DMA_CHANNEL_COUNT] = dma_msix_data [i];
            assign msix_addrs[i + DMA_CHANNEL_COUNT] = dma_msix_addrs[i];

            assign msix_mask [i + DMA_CHANNEL_COUNT*2] = user_msix_mask [i];
            assign msix_data [i + DMA_CHANNEL_COUNT*2] = user_msix_data [i];
            assign msix_addrs[i + DMA_CHANNEL_COUNT*2] = user_msix_addrs[i];

            kdma_rd_engine #(
                .PIPELINE_CAPACITY (PIPELINE_CAPACITY),

                .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH),
                .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH  ),

                .DMA_RQ_DEPTH      (DMA_RQ_DEPTH[i]  )
            ) u_kdma_rd_engine (
                .clk                (clk                  ),
                .rst_n              (dma_resetn           ),

                .dma_addr_i         (dma_addr[i]          ),

                .dma_task_valid_i   (dmard_task_valid [i] ),
                .dma_task_ready_o   (dmard_task_ready [i] ),
                .dma_task_burst_i   (dmard_task_burst [i] ),
                .dma_task_offset_i  (dmard_task_offset[i] ),
                .dma_task_init_i    (dmard_task_init  [i] ),

                .dma_rddata_valid_o (dma_rddata_valid_o[i]),
                .dma_rddata_ready_i (dma_rddata_ready_i[i]),
                .dma_rddata_free_i  (dma_rddata_free_i [i]),
                .dma_rddata_data_o  (dma_rddata_data_o [i]),

                .arvalid_o          (arvalid_o[i]         ),
                .arready_i          (arready_i[i]         ),
                .araddr_o           (araddr_o [i]         ),
                .arlen_o            (arlen_o  [i]         ),
                .arid_o             (arid_o   [i]         ),
                .arburst_o          (arburst_o[i]         ),
                .arsize_o           (arsize_o [i]         ),

                .rvalid_i           (rvalid_i [i]         ),
                .rready_o           (rready_o [i]         ),
                .rdata_i            (rdata_i  [i]         ),
                .rlast_i            (rlast_i  [i]         ),
                .rresp_i            (rresp_i  [i]         ),
                .rid_i              (rid_i    [i]         ),

                .rd_irq_sts_o       (dma_rd_irq_sts[i]    ),
                .rd_irq_clr_i       (dma_rd_irq_clr[i]    )
            );

            kdma_wr_engine #(
                .PIPELINE_CAPACITY (PIPELINE_CAPACITY),

                .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH),
                .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH  ),

                .DMA_WQ_DEPTH      (DMA_WQ_DEPTH[i]  )
            ) u_kdma_wr_engine (
                .clk                (clk                  ),
                .rst_n              (dma_resetn           ),

                .dma_addr_i         (dma_addr[i]          ),

                .dma_task_valid_i   (dmawr_task_valid [i] ),
                .dma_task_ready_o   (dmawr_task_ready [i] ),
                .dma_task_burst_i   (dmawr_task_burst [i] ),
                .dma_task_offset_i  (dmawr_task_offset[i] ),
                .dma_task_init_i    (dmawr_task_init  [i] ),

                .dma_wrdata_valid_i (dma_wrdata_valid_i[i]),
                .dma_wrdata_ready_o (dma_wrdata_ready_o[i]),
                .dma_wrdata_count_i (dma_wrdata_count_i[i]),
                .dma_wrdata_data_i  (dma_wrdata_data_i [i]),

                .awvalid_o          (awvalid_o[i]         ),
                .awready_i          (awready_i[i]         ),
                .awaddr_o           (awaddr_o [i]         ),
                .awlen_o            (awlen_o  [i]         ),
                .awid_o             (awid_o   [i]         ),
                .awburst_o          (awburst_o[i]         ),
                .awsize_o           (awsize_o [i]         ),

                .wvalid_o           (wvalid_o [i]         ),
                .wready_i           (wready_i [i]         ),
                .wdata_o            (wdata_o  [i]         ),
                .wlast_o            (wlast_o  [i]         ),
                .wstrb_o            (wstrb_o  [i]         ),

                .bvalid_i           (bvalid_i [i]         ),
                .bready_o           (bready_o [i]         ),
                .bid_i              (bid_i    [i]         ),
                .bresp_i            (bresp_i  [i]         ),

                .wr_irq_sts_o       (dma_wr_irq_sts[i]    ),
                .wr_irq_clr_i       (dma_wr_irq_clr[i]    )
            );
        end
    endgenerate

endmodule