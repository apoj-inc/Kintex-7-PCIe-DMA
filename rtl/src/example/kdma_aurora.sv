module kdma_aurora #(
    parameter     BAR_COUNT                             = 4         ,

    parameter     DMA_CHANNEL_COUNT                     = 8         ,
    parameter     PIPELINE_CAPACITY                     = 4         ,

    parameter     DMA_BYTES_WIDTH                       = 22        ,
    parameter     DMA_OFFFSET_WIDTH                     = 22        ,

    parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{8{64  }},
    parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{1024}},
    parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{8{64  }},
    parameter     DMA_TQ_DEPTH                          = 8         ,

    parameter     MAX_WQ_DEPTH                          = 1024      ,
    parameter     MAX_RQ_DEPTH                          = 64        ,

    parameter AXI_ID_WIDTH      = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY),
    parameter DMA_WQ_ADDR_WIDTH = $clog2(MAX_WQ_DEPTH)                                  ,
    parameter DMA_RQ_ADDR_WIDTH = $clog2(MAX_RQ_DEPTH)                                  ,
    parameter MSIX_COUNT        = DMA_CHANNEL_COUNT                                     
) (
    input  logic                         pcie_clk_in_p,
    input  logic                         pcie_clk_in_n,

    input  logic                         perst_n      ,

    output logic                         pci_exp_tx0_p,
    output logic                         pci_exp_tx0_n,
    output logic                         pci_exp_tx1_p,
    output logic                         pci_exp_tx1_n,
    output logic                         pci_exp_tx2_p,
    output logic                         pci_exp_tx2_n,
    output logic                         pci_exp_tx3_p,
    output logic                         pci_exp_tx3_n,

    input  logic                         pci_exp_rx0_p,
    input  logic                         pci_exp_rx0_n,
    input  logic                         pci_exp_rx1_p,
    input  logic                         pci_exp_rx1_n,
    input  logic                         pci_exp_rx2_p,
    input  logic                         pci_exp_rx2_n,
    input  logic                         pci_exp_rx3_p,
    input  logic                         pci_exp_rx3_n,

    input  logic                         clk_100m     ,

    input  logic                         aurora_clk_p ,
    input  logic                         aurora_clk_n ,

    output logic                         aurora_tx_p  ,
    output logic                         aurora_tx_n  ,

    input  logic                         aurora_rx_p  ,
    input  logic                         aurora_rx_n  
);

    logic dma_clk;
    logic dma_rstn, dma_rstn_synced;
    logic pcie_rstn;

    logic aurora_clk;

    logic                         dmard_data_valid_wr [DMA_CHANNEL_COUNT];
    logic                         dmard_data_ready_wr [DMA_CHANNEL_COUNT];
    logic [127:0]                 dmard_data_data_wr  [DMA_CHANNEL_COUNT];
    logic [DMA_RQ_ADDR_WIDTH:0]   dmard_data_free     [DMA_CHANNEL_COUNT];

    logic [DMA_CHANNEL_COUNT-1:0] dmard_data_valid_rd                    ;
    logic [DMA_CHANNEL_COUNT-1:0] dmard_data_ready_rd                    ;
    logic [127:0]                 dmard_data_data_rd  [DMA_CHANNEL_COUNT];


    logic                         dmawr_data_valid_rd [DMA_CHANNEL_COUNT];
    logic                         dmawr_data_ready_rd [DMA_CHANNEL_COUNT];
    logic [127:0]                 dmawr_data_data_rd  [DMA_CHANNEL_COUNT];
    logic [DMA_WQ_ADDR_WIDTH:0]   dmard_data_count    [DMA_CHANNEL_COUNT];

    logic [DMA_CHANNEL_COUNT-1:0] dmawr_data_valid_wr                    ;
    logic [DMA_CHANNEL_COUNT-1:0] dmawr_data_ready_wr                    ;
    logic [127:0]                 dmawr_data_data_wr                     ;

    logic         user_psel   ;
    logic         user_penable;
    logic         user_pready ;
    logic [63:0]  user_paddr  ;
    logic         user_pwrite ;
    logic [127:0] user_pwdata ;
    logic [15:0]  user_pstrb  ;
    logic [127:0] user_prdata ;

    logic [DMA_CHANNEL_COUNT-1:0] user_irq;

    sync_rst dma_to_aurora_rstsync (
        .rst_n_i (dma_rstn       ),

        .clk_tgt (aurora_clk     ),
        .rst_n_o (dma_rstn_synced)
    );

    kdma_aurora_connector #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_aurora_connector (
        .clk_100m         (clk_100m           ),

        .gtx_clk_p        (aurora_clk_p       ),
        .gtx_clk_n        (aurora_clk_n       ),

        .gtx_rx_p         (aurora_rx_p        ),
        .gtx_rx_n         (aurora_rx_n        ),

        .gtx_tx_p         (aurora_tx_p        ),
        .gtx_tx_n         (aurora_tx_n        ),

        .user_clk_o       (aurora_clk         ),
        .dma_rstn_i       (dma_rstn_synced    ),

        .dma_data_valid_i (dmard_data_valid_rd),
        .dma_data_ready_o (dmard_data_ready_rd),
        .dma_data_data_i  (dmard_data_data_rd ),
        .dma_data_free_i  (dmard_data_free    ),

        .dma_data_valid_o (dmawr_data_valid_wr),
        .dma_data_data_o  (dmawr_data_data_wr )
    );

    generate
        genvar i;
        
        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : echo_fifos

            logic [6:0] count;

            cdc_stream_afifo #(
                .DATA_WIDTH (128                    ),
                .ADDR_WIDTH ($clog2(DMA_RQ_DEPTH[i]))
            ) dmard_fifo (
                .clk_wr   (dma_clk               ),
                .rst_n_wr (dma_rstn              ),

                .data_i   (dmard_data_data_wr [i]),
                .valid_i  (dmard_data_valid_wr[i]),
                .ready_o  (dmard_data_ready_wr[i]),
                .free_o   (dmard_data_free    [i]),

                .clk_rd   (aurora_clk            ),
                .rst_n_rd (dma_rstn_synced       ),

                .data_o   (dmard_data_data_rd [i]),
                .valid_o  (dmard_data_valid_rd[i]),
                .ready_i  (dmard_data_ready_rd[i]),
                .count_o  (count                 )
            );

            cdc_stream_afifo #(
                .DATA_WIDTH (128                    ),
                .ADDR_WIDTH ($clog2(DMA_WQ_DEPTH[i]))
            ) dmawr_fifo (
                .clk_wr   (aurora_clk            ),
                .rst_n_wr (dma_rstn_synced       ),

                .data_i   (dmawr_data_data_wr    ),
                .valid_i  (dmawr_data_valid_wr[i]),
                .ready_o  (dmawr_data_ready_wr[i]),
                .free_o   (                      ),

                .clk_rd   (dma_clk               ),
                .rst_n_rd (dma_rstn              ),

                .data_o   (dmawr_data_data_rd [i]),
                .valid_o  (dmawr_data_valid_rd[i]),
                .ready_i  (dmawr_data_ready_rd[i]),
                .count_o  (dmard_data_count   [i])
            );
        end
    endgenerate

    kdma_user_flatten #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_user_flatten (
        .clk           (dma_clk     ),
        .rst_n         (pcie_rstn   ),

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
        .clk_in_p           (pcie_clk_in_p      ),
        .clk_in_n           (pcie_clk_in_n      ),

        .sys_rst_n          (perst_n            ),

        .pci_exp_tx0_p      (pci_exp_tx0_p      ),
        .pci_exp_tx0_n      (pci_exp_tx0_n      ),
        .pci_exp_tx1_p      (pci_exp_tx1_p      ),
        .pci_exp_tx1_n      (pci_exp_tx1_n      ),
        .pci_exp_tx2_p      (pci_exp_tx2_p      ),
        .pci_exp_tx2_n      (pci_exp_tx2_n      ),
        .pci_exp_tx3_p      (pci_exp_tx3_p      ),
        .pci_exp_tx3_n      (pci_exp_tx3_n      ),

        .pci_exp_rx0_p      (pci_exp_rx0_p      ),
        .pci_exp_rx0_n      (pci_exp_rx0_n      ),
        .pci_exp_rx1_p      (pci_exp_rx1_p      ),
        .pci_exp_rx1_n      (pci_exp_rx1_n      ),
        .pci_exp_rx2_p      (pci_exp_rx2_p      ),
        .pci_exp_rx2_n      (pci_exp_rx2_n      ),
        .pci_exp_rx3_p      (pci_exp_rx3_p      ),
        .pci_exp_rx3_n      (pci_exp_rx3_n      ),

        .dma_wrdata_valid_i (dmawr_data_valid_rd),
        .dma_wrdata_ready_o (dmawr_data_ready_rd),
        .dma_wrdata_count_i (dmard_data_count   ),
        .dma_wrdata_data_i  (dmawr_data_data_rd ),

        .dma_rddata_valid_o (dmard_data_valid_wr),
        .dma_rddata_ready_i (dmard_data_ready_wr),
        .dma_rddata_free_i  (dmard_data_free    ),
        .dma_rddata_data_o  (dmard_data_data_wr ),

        .user_psel_o        (user_psel          ),
        .user_penable_o     (user_penable       ),
        .user_pready_i      (user_pready        ),
        .user_paddr_o       (user_paddr         ),
        .user_pwrite_o      (user_pwrite        ),
        .user_pwdata_o      (user_pwdata        ),
        .user_pstrb_o       (user_pstrb         ),
        .user_prdata_i      (user_prdata        ),

        .user_irq_i         (user_irq           ),

        .dma_clk_o          (dma_clk            ),
        .dma_resetn_o       (dma_rstn           ),
        .pcie_resetn_o      (pcie_rstn          )

    );

endmodule