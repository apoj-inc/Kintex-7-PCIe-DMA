module kdma_echodevice #(
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
    input  logic [1:0]                   msix_bresp_i                            
);

    logic                       dma_wrdata_valid [DMA_CHANNEL_COUNT];
    logic                       dma_wrdata_ready [DMA_CHANNEL_COUNT];
    logic [DMA_WQ_ADDR_WIDTH:0] dma_wrdata_count [DMA_CHANNEL_COUNT];
    logic [127:0]               dma_wrdata_data  [DMA_CHANNEL_COUNT];

    logic                       dma_rddata_valid [DMA_CHANNEL_COUNT];
    logic                       dma_rddata_ready [DMA_CHANNEL_COUNT];
    logic [DMA_RQ_ADDR_WIDTH:0] dma_rddata_free  [DMA_CHANNEL_COUNT];
    logic [127:0]               dma_rddata_data  [DMA_CHANNEL_COUNT];

    logic dma_resetn;

    generate
        genvar i;
        
        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : echo_fifos
            logic         file_wr_valid, file_rd_valid;
            logic         file_wr_ready, file_rd_ready;
            logic [127:0] file_wr_data , file_rd_data ;

            stream_fifo #(
                .DATA_WIDTH (128            ),
                .FIFO_DEPTH (DMA_RQ_DEPTH[i])
            ) dmard_fifo (
                .ACLK    (clk       ),
                .ARESETn (dma_resetn),

                .data_i  (dma_rddata_data [i]),
                .valid_i (dma_rddata_valid[i]),
                .ready_o (dma_rddata_ready[i]),
                .free_o  (dma_rddata_free [i]),

                .data_o  (file_wr_data ),
                .valid_o (file_wr_valid),
                .ready_i (file_wr_ready),
                .count_o ()
            );

            stream_fifo #(
                .DATA_WIDTH (128 ),
                .FIFO_DEPTH (1024)
            ) file_fifo (
                .ACLK    (clk       ),
                .ARESETn (dma_resetn),

                .data_i  (file_wr_data ),
                .valid_i (file_wr_valid),
                .ready_o (file_wr_ready),
                .free_o  (),

                .data_o  (file_rd_data ),
                .valid_o (file_rd_valid),
                .ready_i (file_rd_ready),
                .count_o ()
            );
            
            stream_fifo #(
                .DATA_WIDTH (128            ),
                .FIFO_DEPTH (DMA_WQ_DEPTH[i])
            ) dmawr_fifo (
                .ACLK    (clk       ),
                .ARESETn (dma_resetn),

                .data_i  (file_rd_data ),
                .valid_i (file_rd_valid),
                .ready_o (file_rd_ready),
                .free_o  (),

                .data_o  (dma_wrdata_data [i]),
                .valid_o (dma_wrdata_valid[i]),
                .ready_i (dma_wrdata_ready[i]),
                .count_o (dma_wrdata_count[i])
            );
        end
    endgenerate

    kdma_top #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT ),
        .PIPELINE_CAPACITY (PIPELINE_CAPACITY ),

        .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH   ),
        .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH ),

        .DMA_WORD_BYTES    (DMA_WORD_BYTES    ),
        .DMA_WQ_DEPTH      (DMA_WQ_DEPTH      ),
        .DMA_RQ_DEPTH      (DMA_RQ_DEPTH      ),
        .DMA_TQ_DEPTH      (DMA_TQ_DEPTH      ),

        .MAX_WQ_DEPTH      (MAX_WQ_DEPTH      ),
        .MAX_RQ_DEPTH      (MAX_RQ_DEPTH      )
    ) u_kdma_top (
        .clk                (clk             ),
        .rst_n              (rst_n           ),

        .csr_psel_i         (csr_psel_i      ),
        .csr_penable_i      (csr_penable_i   ),
        .csr_pready_o       (csr_pready_o    ),
        .csr_paddr_i        (csr_paddr_i     ),
        .csr_pwrite_i       (csr_pwrite_i    ),
        .csr_pwdata_i       (csr_pwdata_i    ),
        .csr_pstrb_i        (csr_pstrb_i     ),
        .csr_prdata_o       (csr_prdata_o    ),

        .msix_psel_i        (msix_psel_i     ),
        .msix_penable_i     (msix_penable_i  ),
        .msix_pready_o      (msix_pready_o   ),
        .msix_paddr_i       (msix_paddr_i    ),
        .msix_pwrite_i      (msix_pwrite_i   ),
        .msix_pwdata_i      (msix_pwdata_i   ),
        .msix_pstrb_i       (msix_pstrb_i    ),
        .msix_prdata_o      (msix_prdata_o   ),

        .dec_psel_i         (dec_psel_i      ),
        .dec_penable_i      (dec_penable_i   ),
        .dec_pready_o       (dec_pready_o    ),
        .dec_paddr_i        (dec_paddr_i     ),
        .dec_pwrite_i       (dec_pwrite_i    ),
        .dec_pwdata_i       (dec_pwdata_i    ),
        .dec_pstrb_i        (dec_pstrb_i     ),
        .dec_prdata_o       (dec_prdata_o    ),

        .user_irq_i         (user_irq_i      ),

        .arvalid_o          (arvalid_o       ),
        .arready_i          (arready_i       ),
        .araddr_o           (araddr_o        ),
        .arlen_o            (arlen_o         ),
        .arid_o             (arid_o          ),
        .arburst_o          (arburst_o       ),
        .arsize_o           (arsize_o        ),

        .rvalid_i           (rvalid_i        ),
        .rready_o           (rready_o        ),
        .rdata_i            (rdata_i         ),
        .rlast_i            (rlast_i         ),
        .rresp_i            (rresp_i         ),
        .rid_i              (rid_i           ),

        .awvalid_o          (awvalid_o       ),
        .awready_i          (awready_i       ),
        .awaddr_o           (awaddr_o        ),
        .awlen_o            (awlen_o         ),
        .awid_o             (awid_o          ),
        .awburst_o          (awburst_o       ),
        .awsize_o           (awsize_o        ),

        .wvalid_o           (wvalid_o        ),
        .wready_i           (wready_i        ),
        .wdata_o            (wdata_o         ),
        .wlast_o            (wlast_o         ),
        .wstrb_o            (wstrb_o         ),

        .bvalid_i           (bvalid_i        ),
        .bready_o           (bready_o        ),
        .bid_i              (bid_i           ),
        .bresp_i            (bresp_i         ),

        .msix_awvalid_o     (msix_awvalid_o  ),
        .msix_awready_i     (msix_awready_i  ),
        .msix_awaddr_o      (msix_awaddr_o   ),
        .msix_awlen_o       (msix_awlen_o    ),
        .msix_awid_o        (msix_awid_o     ),
        .msix_awburst_o     (msix_awburst_o  ),
        .msix_awsize_o      (msix_awsize_o   ),

        .msix_wvalid_o      (msix_wvalid_o   ),
        .msix_wready_i      (msix_wready_i   ),
        .msix_wdata_o       (msix_wdata_o    ),
        .msix_wlast_o       (msix_wlast_o    ),
        .msix_wstrb_o       (msix_wstrb_o    ),

        .msix_bvalid_i      (msix_bvalid_i   ),
        .msix_bready_o      (msix_bready_o   ),
        .msix_bid_i         (msix_bid_i      ),
        .msix_bresp_i       (msix_bresp_i    ),

        .dma_wrdata_valid_i (dma_wrdata_valid),
        .dma_wrdata_ready_o (dma_wrdata_ready),
        .dma_wrdata_count_i (dma_wrdata_count),
        .dma_wrdata_data_i  (dma_wrdata_data ),

        .dma_rddata_valid_o (dma_rddata_valid),
        .dma_rddata_ready_i (dma_rddata_ready),
        .dma_rddata_free_i  (dma_rddata_free ),
        .dma_rddata_data_o  (dma_rddata_data ),

        .dma_resetn_o       (dma_resetn      )                     
    );
    
endmodule