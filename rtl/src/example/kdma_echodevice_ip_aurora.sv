module kdma_echodevice_ip_aurora #(
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

    kdma_aurora_example u_kdma_aurora_example (
        .clk_100m  (clk_100m    ),

        .gtx_clk_p (aurora_clk_p),
        .gtx_clk_n (aurora_clk_n),

        .gtx_rx_p  (aurora_rx_p ),
        .gtx_rx_n  (aurora_rx_n ),

        .gtx_tx_p  (aurora_tx_p ),
        .gtx_tx_n  (aurora_tx_n )
    );

    kdma_echodevice_ip #(
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
    ) u_kdma_echodevice_ip (
        .clk_in_p      (pcie_clk_in_p),
        .clk_in_n      (pcie_clk_in_n),

        .sys_rst_n     (perst_n      ),

        .pci_exp_tx0_p (pci_exp_tx0_p),
        .pci_exp_tx0_n (pci_exp_tx0_n),
        .pci_exp_tx1_p (pci_exp_tx1_p),
        .pci_exp_tx1_n (pci_exp_tx1_n),
        .pci_exp_tx2_p (pci_exp_tx2_p),
        .pci_exp_tx2_n (pci_exp_tx2_n),
        .pci_exp_tx3_p (pci_exp_tx3_p),
        .pci_exp_tx3_n (pci_exp_tx3_n),

        .pci_exp_rx0_p (pci_exp_rx0_p),
        .pci_exp_rx0_n (pci_exp_rx0_n),
        .pci_exp_rx1_p (pci_exp_rx1_p),
        .pci_exp_rx1_n (pci_exp_rx1_n),
        .pci_exp_rx2_p (pci_exp_rx2_p),
        .pci_exp_rx2_n (pci_exp_rx2_n),
        .pci_exp_rx3_p (pci_exp_rx3_p),
        .pci_exp_rx3_n (pci_exp_rx3_n)
    );

endmodule