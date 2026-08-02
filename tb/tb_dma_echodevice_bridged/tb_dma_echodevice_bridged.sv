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

initial begin
    test_done = '0;
    clk = 0;
    #2;
    rst_n = 0;
    pcie_ready_i = 1;
    pcie_valid_i = 0;
    user_irq_i = '0;

    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    
    test_done = '1;
end

endmodule