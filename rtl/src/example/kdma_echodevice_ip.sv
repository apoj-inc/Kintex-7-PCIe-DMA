module kdma_echodevice_ip #(
    parameter     BAR_COUNT                             = 4         ,

    parameter     DMA_CHANNEL_COUNT                     = 8         ,
    parameter     PIPELINE_CAPACITY                     = 4         ,

    parameter     DMA_BYTES_WIDTH                       = 22        ,
    parameter     DMA_OFFFSET_WIDTH                     = 22        ,

    parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{8{64  }},
    parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{64  }},
    parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{64  }},
    parameter     DMA_TQ_DEPTH                          = 8         ,

    parameter     MAX_WQ_DEPTH                          = 64        ,
    parameter     MAX_RQ_DEPTH                          = 64        ,

    parameter AXI_ID_WIDTH      = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY),
    parameter DMA_WQ_ADDR_WIDTH = $clog2(MAX_WQ_DEPTH)                                  ,
    parameter DMA_RQ_ADDR_WIDTH = $clog2(MAX_RQ_DEPTH)                                  ,
    parameter MSIX_COUNT        = DMA_CHANNEL_COUNT                                     
) (
    input  logic                         clk_in_p                                ,
    input  logic                         clk_in_n                                ,

    input  logic                         sys_rst_n                               ,

    output logic                         pci_exp_tx0_p                           ,
    output logic                         pci_exp_tx0_n                           ,
    output logic                         pci_exp_tx1_p                           ,
    output logic                         pci_exp_tx1_n                           ,
    output logic                         pci_exp_tx2_p                           ,
    output logic                         pci_exp_tx2_n                           ,
    output logic                         pci_exp_tx3_p                           ,
    output logic                         pci_exp_tx3_n                           ,

    input  logic                         pci_exp_rx0_p                           ,
    input  logic                         pci_exp_rx0_n                           ,
    input  logic                         pci_exp_rx1_p                           ,
    input  logic                         pci_exp_rx1_n                           ,
    input  logic                         pci_exp_rx2_p                           ,
    input  logic                         pci_exp_rx2_n                           ,
    input  logic                         pci_exp_rx3_p                           ,
    input  logic                         pci_exp_rx3_n                                                    
);

    logic                       dma_wrdata_valid [DMA_CHANNEL_COUNT];
    logic                       dma_wrdata_ready [DMA_CHANNEL_COUNT];
    logic [DMA_WQ_ADDR_WIDTH:0] dma_wrdata_count [DMA_CHANNEL_COUNT];
    logic [127:0]               dma_wrdata_data  [DMA_CHANNEL_COUNT];

    logic                       dma_rddata_valid [DMA_CHANNEL_COUNT];
    logic                       dma_rddata_ready [DMA_CHANNEL_COUNT];
    logic [DMA_RQ_ADDR_WIDTH:0] dma_rddata_free  [DMA_CHANNEL_COUNT];
    logic [127:0]               dma_rddata_data  [DMA_CHANNEL_COUNT];

    logic dma_clk    ;
    logic pcie_resetn;
    logic dma_resetn ;

    logic         user_psel   ;
    logic         user_penable;
    logic         user_pready ;
    logic [63:0]  user_paddr  ;
    logic         user_pwrite ;
    logic [127:0] user_pwdata ;
    logic [15:0]  user_pstrb  ;
    logic [127:0] user_prdata ;

    logic [DMA_CHANNEL_COUNT-1:0] user_irq;

    kdma_user_flatten #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_user_flatten (
        .clk           (dma_clk     ),
        .rst_n         (pcie_resetn ),

        .bar_psel_i    (user_psel   ),
        .bar_penable_i (user_penable),
        .bar_pready_o  (user_pready ),
        .bar_paddr_i   (user_paddr  ),
        .bar_pwrite_i  (user_pwrite ),
        .bar_pwdata_i  (user_pwdata ),
        .bar_pstrb_i   (user_pstrb  ),
        .bar_prdata_o  (user_prdata ),

        .user_irq_o    (user_irq    )
    );

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
                .ACLK    (dma_clk   ),
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
                .ACLK    (dma_clk   ),
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
                .ACLK    (dma_clk   ),
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

    kdma_toplevel #(
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
    ) u_kdma_toplevel (
        .clk_in_p           (clk_in_p        ),
        .clk_in_n           (clk_in_n        ),

        .sys_rst_n          (sys_rst_n       ),

        .pci_exp_tx0_p      (pci_exp_tx0_p   ),
        .pci_exp_tx0_n      (pci_exp_tx0_n   ),
        .pci_exp_tx1_p      (pci_exp_tx1_p   ),
        .pci_exp_tx1_n      (pci_exp_tx1_n   ),
        .pci_exp_tx2_p      (pci_exp_tx2_p   ),
        .pci_exp_tx2_n      (pci_exp_tx2_n   ),
        .pci_exp_tx3_p      (pci_exp_tx3_p   ),
        .pci_exp_tx3_n      (pci_exp_tx3_n   ),

        .pci_exp_rx0_p      (pci_exp_rx0_p   ),
        .pci_exp_rx0_n      (pci_exp_rx0_n   ),
        .pci_exp_rx1_p      (pci_exp_rx1_p   ),
        .pci_exp_rx1_n      (pci_exp_rx1_n   ),
        .pci_exp_rx2_p      (pci_exp_rx2_p   ),
        .pci_exp_rx2_n      (pci_exp_rx2_n   ),
        .pci_exp_rx3_p      (pci_exp_rx3_p   ),
        .pci_exp_rx3_n      (pci_exp_rx3_n   ),

        .dma_wrdata_valid_i (dma_wrdata_valid),
        .dma_wrdata_ready_o (dma_wrdata_ready),
        .dma_wrdata_count_i (dma_wrdata_count),
        .dma_wrdata_data_i  (dma_wrdata_data ),

        .dma_rddata_valid_o (dma_rddata_valid),
        .dma_rddata_ready_i (dma_rddata_ready),
        .dma_rddata_free_i  (dma_rddata_free ),
        .dma_rddata_data_o  (dma_rddata_data ),

        .user_psel_o        (user_psel       ),
        .user_penable_o     (user_penable    ),
        .user_pready_i      (user_pready     ),
        .user_paddr_o       (user_paddr      ),
        .user_pwrite_o      (user_pwrite     ),
        .user_pwdata_o      (user_pwdata     ),
        .user_pstrb_o       (user_pstrb      ),
        .user_prdata_i      (user_prdata     ),

        .user_irq_i         (user_irq        ),

        .dma_clk_o          (dma_clk         ),
        .dma_resetn_o       (dma_resetn      ),
        .pcie_resetn_o      (pcie_resetn     )
    );
    
endmodule