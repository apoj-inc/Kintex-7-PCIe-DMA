import kdma_decoder_am_pkg::*;

module kdma_decoder_flatten #(
    parameter DMA_CHANNEL_COUNT = 8
) (
    input  logic                         clk                                  ,
    input  logic                         rst_n                                ,

    input  logic                         bar_psel_i                           ,
    input  logic                         bar_penable_i                        ,
    output logic                         bar_pready_o                         ,
    input  logic [63:0]                  bar_paddr_i                          ,
    input  logic                         bar_pwrite_i                         ,
    input  logic [127:0]                 bar_pwdata_i                         ,
    input  logic [15:0]                  bar_pstrb_i                          ,
    output logic [127:0]                 bar_prdata_o                         ,

    output logic [21:0]                  bytecount_wr_o    [DMA_CHANNEL_COUNT],
    output logic [21:0]                  offset_wr_o       [DMA_CHANNEL_COUNT],
    output logic [21:0]                  bytecount_rd_o    [DMA_CHANNEL_COUNT],
    output logic [21:0]                  offset_rd_o       [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] btcnt_wr_swmod_o                     ,
    output logic [DMA_CHANNEL_COUNT-1:0] ofst_wr_swmod_o                      ,
    output logic [DMA_CHANNEL_COUNT-1:0] btcnt_rd_swmod_o                     ,
    output logic [DMA_CHANNEL_COUNT-1:0] ofst_rd_swmod_o                      
);

kdma_decoder_am__out_t hwif_out;

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
            bytecount_wr_o[i]   = hwif_out.DMA_TASK_REG[i].BYTECNT_WR.value;
            offset_wr_o[i]      = hwif_out.DMA_TASK_REG[i].OFFSET_WR.value;
            bytecount_rd_o[i]   = hwif_out.DMA_TASK_REG[i].BYTECNT_RD.value;
            offset_rd_o[i]      = hwif_out.DMA_TASK_REG[i].OFFSET_RD.value;
            btcnt_wr_swmod_o[i] = hwif_out.DMA_TASK_REG[i].BYTECNT_WR.swmod;
            ofst_wr_swmod_o[i]  = hwif_out.DMA_TASK_REG[i].OFFSET_WR.swmod;
            btcnt_rd_swmod_o[i] = hwif_out.DMA_TASK_REG[i].BYTECNT_RD.swmod;
            ofst_rd_swmod_o[i]  = hwif_out.DMA_TASK_REG[i].OFFSET_RD.swmod;
        end
    end
endgenerate

kdma_decoder_am u_kdma_decoder_am (
    .clk      (clk     ),
    .arst_n   (rst_n   ),

    .s_apb    (apb_if  ),

    .hwif_out (hwif_out)
);

    
endmodule