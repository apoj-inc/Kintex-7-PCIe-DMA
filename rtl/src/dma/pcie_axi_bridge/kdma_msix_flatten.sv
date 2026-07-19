import kdma_msix_am_pkg::*;

module kdma_msix_flatten #(
    parameter DMA_CHANNEL_COUNT = 8,

    parameter DMA_MSIX_COUNT  = DMA_CHANNEL_COUNT,
    parameter USER_MSIX_COUNT = DMA_CHANNEL_COUNT
) (
    input  logic         clk                                ,
    input  logic         rst_n                              ,

    input  logic         bar_psel_i                         ,
    input  logic         bar_penable_i                      ,
    output logic         bar_pready_o                       ,
    input  logic [63:0]  bar_paddr_i                        ,
    input  logic         bar_pwrite_i                       ,
    input  logic [127:0] bar_pwdata_i                       ,
    input  logic [15:0]  bar_pstrb_i                        ,
    output logic [127:0] bar_prdata_o                       ,
    
    output logic [31:0]  dma_msix_mask_o   [DMA_MSIX_COUNT] ,
    output logic [31:0]  dma_msix_data_o   [DMA_MSIX_COUNT] ,
    output logic [63:0]  dma_msix_addrs_o  [DMA_MSIX_COUNT] ,

    output logic [31:0]  user_msix_mask_o  [USER_MSIX_COUNT],
    output logic [31:0]  user_msix_data_o  [USER_MSIX_COUNT],
    output logic [63:0]  user_msix_addrs_o [USER_MSIX_COUNT]
);

kdma_msix_am__out_t hwif_out;

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

generate
    genvar i;

    for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : dma_msix
        always_comb begin
            dma_msix_addrs_o[i] = hwif_out.MSIX_ENTRY_REG[i].ADDR.value;
            dma_msix_data_o[i]  = hwif_out.MSIX_ENTRY_REG[i].DATA.value;
            dma_msix_mask_o[i]  = hwif_out.MSIX_ENTRY_REG[i].MASK.value;
        end
    end

    for (i = DMA_CHANNEL_COUNT; i < DMA_CHANNEL_COUNT*2; i++) begin : user_msix
        always_comb begin
            user_msix_addrs_o[i] = hwif_out.MSIX_ENTRY_REG[i].ADDR.value;
            user_msix_data_o[i]  = hwif_out.MSIX_ENTRY_REG[i].DATA.value;
            user_msix_mask_o[i]  = hwif_out.MSIX_ENTRY_REG[i].MASK.value;
        end
    end
endgenerate

kdma_msix_am u_kdma_msix_am (
    .clk      (clk     ),
    .arst_n   (rst_n   ),

    .s_apb    (apb_if  ),

    .hwif_out (hwif_out)
);

    
endmodule