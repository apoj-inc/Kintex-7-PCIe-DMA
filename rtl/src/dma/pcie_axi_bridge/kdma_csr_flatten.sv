import kdma_csr_am_pkg::*;

module kdma_csr_flatten #(
    parameter     DMA_CHANNEL_COUNT                = 8         ,

    parameter int DMA_WQ_DEPTH [DMA_CHANNEL_COUNT] = '{8{1024}},
    parameter int DMA_RQ_DEPTH [DMA_CHANNEL_COUNT] = '{8{1024}},
    parameter     DMA_TQ_DEPTH                     = 8         ,

    parameter     MAX_WQ_DEPTH                     = 1024      ,
    parameter     MAX_RQ_DEPTH                     = 1024      ,

    parameter DMA_WQ_ADDR_WIDTH = $clog2(MAX_WQ_DEPTH),
    parameter DMA_RQ_ADDR_WIDTH = $clog2(MAX_RQ_DEPTH),
    parameter DMA_TQ_ADDR_WIDTH = $clog2(DMA_TQ_DEPTH)
) (
    input  logic                         clk                                   ,
    input  logic                         rst_n                                 ,

    input  logic                         bar_psel_i                            ,
    input  logic                         bar_penable_i                         ,
    output logic                         bar_pready_o                          ,
    input  logic [63:0]                  bar_paddr_i                           ,
    input  logic                         bar_pwrite_i                          ,
    input  logic [127:0]                 bar_pwdata_i                          ,
    input  logic [15:0]                  bar_pstrb_i                           ,
    output logic [127:0]                 bar_prdata_o                          ,

    output logic                         dma_reset_o                           ,
    output logic [DMA_CHANNEL_COUNT-1:0] dmawr_irq_clr_o                       ,
    output logic [DMA_CHANNEL_COUNT-1:0] dmard_irq_clr_o                       ,
    output logic [63:0]                  dma_addr_o         [DMA_CHANNEL_COUNT],

    input  logic [DMA_TQ_ADDR_WIDTH:0]   dmawr_task_free_i                     ,
    input  logic [DMA_TQ_ADDR_WIDTH:0]   dmard_task_free_i                     ,
    input  logic [DMA_WQ_ADDR_WIDTH:0]   dmawr_data_count_i [DMA_CHANNEL_COUNT],
    input  logic [DMA_RQ_ADDR_WIDTH:0]   dmard_data_free_i  [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0] dmawr_irq_sts_i                       ,
    input  logic [DMA_CHANNEL_COUNT-1:0] dmard_irq_sts_i                       
);

kdma_csr_am__in_t hwif_in;
kdma_csr_am__out_t hwif_out;

apb4_intf #(
    .DATA_WIDTH (128),
    .ADDR_WIDTH (64 )
) apb_if();

always_comb begin
    apb_if.PSEL    = bar_psel_i   ;
    apb_if.PENABLE = bar_penable_i;
    apb_if.PWRITE  = bar_pwrite_i ;
    apb_if.PPROT   = '0           ;
    apb_if.PADDR   = bar_paddr_i  ;
    apb_if.PWDATA  = bar_pwdata_i ;
    apb_if.PSTRB   = bar_pstrb_i  ;

    bar_prdata_o   = apb_if.PRDATA;
    bar_pready_o   = apb_if.PREADY;
end

always_comb begin
    dma_reset_o = hwif_out.GLOBAL_REG.DMA_RESET.value;
    

    hwif_in.GLOBAL_REG.STRUCT_0_PTR.next    = 'h40             ;
    hwif_in.GLOBAL_REG.DMAWR_TASK_FREE.next = dmawr_task_free_i;
    hwif_in.GLOBAL_REG.DMARD_TASK_FREE.next = dmard_task_free_i;
end

generate
    genvar i;

    for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : struct_signals
        always_comb begin
            dmawr_irq_clr_o[i] = hwif_out.STRUCT_REGS[i].IRQ_CSR_REG.DMAWR_IRQ_CLR.value  ;
            dmard_irq_clr_o[i] = hwif_out.STRUCT_REGS[i].IRQ_CSR_REG.DMARD_IRQ_CLR.value  ;

            dma_addr_o[i]      = hwif_out.STRUCT_REGS[i].PTR_ADDR_WIDTH_REG.DMA_ADDR.value;


            hwif_in.STRUCT_REGS[i].PTR_ADDR_WIDTH_REG.STRUCT_NEXT_PTR.next = 'h40 * (i+2)         ;
            hwif_in.STRUCT_REGS[i].FIFO_INFO_REG.MAX_WR_SIZE.next          = DMA_WQ_DEPTH[i] * 16 ;
            hwif_in.STRUCT_REGS[i].FIFO_INFO_REG.MAX_RD_SIZE.next          = DMA_RQ_DEPTH[i] * 16 ;
            hwif_in.STRUCT_REGS[i].FIFO_INFO_REG.WDATA_CONUT.next          = dmawr_data_count_i[i];
            hwif_in.STRUCT_REGS[i].FIFO_INFO_REG.RDATA_FREE.next           = dmard_data_free_i[i] ;
            hwif_in.STRUCT_REGS[i].IRQ_CSR_REG.DMAWR_IRQ_STS.next          = dmawr_irq_sts_i[i]   ;
            hwif_in.STRUCT_REGS[i].IRQ_CSR_REG.DMARD_IRQ_STS.next          = dmard_irq_sts_i[i]   ;
        end
    end
endgenerate

kdma_csr_am u_kdma_csr_am (
    .clk      (clk     ),
    .arst_n   (rst_n   ),

    .s_apb    (apb_if  ),

    .hwif_in  (hwif_in ),
    .hwif_out (hwif_out)
);

    
endmodule