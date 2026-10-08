import kdma_decoder_am_pkg::*;

module kdma_decoder_flatten #(
    parameter DMA_CHANNEL_COUNT = 8
) (
    input  logic                         clk                                     ,
    input  logic                         rst_n                                   ,

    input  logic                         bar_psel_i                              ,
    input  logic                         bar_penable_i                           ,
    output logic                         bar_pready_o                            ,
    input  logic [63:0]                  bar_paddr_i                             ,
    input  logic                         bar_pwrite_i                            ,
    input  logic [127:0]                 bar_pwdata_i                            ,
    input  logic [15:0]                  bar_pstrb_i                             ,
    output logic [127:0]                 bar_prdata_o                            ,

    output logic [21:0]                  bytecount_wr_data_o  [DMA_CHANNEL_COUNT],
    output logic [21:0]                  offset_wr_data_o     [DMA_CHANNEL_COUNT],
    output logic [21:0]                  bytecount_rd_data_o  [DMA_CHANNEL_COUNT],
    output logic [21:0]                  offset_rd_data_o     [DMA_CHANNEL_COUNT],

    output logic [21:0]                  bytecount_wr_biten_o [DMA_CHANNEL_COUNT],
    output logic [21:0]                  offset_wr_biten_o    [DMA_CHANNEL_COUNT],
    output logic [21:0]                  bytecount_rd_biten_o [DMA_CHANNEL_COUNT],
    output logic [21:0]                  offset_rd_biten_o    [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] valid_o                                 ,
    input  logic [DMA_CHANNEL_COUNT-1:0] ready_i                                 


);

kdma_decoder_am__in_t  hwif_in;
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
            bytecount_wr_data_o  [i] = hwif_out.DMA_TASK_REG[i].wr_data.BYTECNT_WR;
            offset_wr_data_o     [i] = hwif_out.DMA_TASK_REG[i].wr_data.OFFSET_WR;
            bytecount_rd_data_o  [i] = hwif_out.DMA_TASK_REG[i].wr_data.BYTECNT_RD;
            offset_rd_data_o     [i] = hwif_out.DMA_TASK_REG[i].wr_data.OFFSET_RD;
            
            bytecount_wr_biten_o [i] = hwif_out.DMA_TASK_REG[i].wr_biten.BYTECNT_WR;
            offset_wr_biten_o    [i] = hwif_out.DMA_TASK_REG[i].wr_biten.OFFSET_WR;
            bytecount_rd_biten_o [i] = hwif_out.DMA_TASK_REG[i].wr_biten.BYTECNT_RD;
            offset_rd_biten_o    [i] = hwif_out.DMA_TASK_REG[i].wr_biten.OFFSET_RD;

            valid_o              [i] = hwif_out.DMA_TASK_REG[i].req &
                                       hwif_out.DMA_TASK_REG[i].req_is_wr ;
            
            hwif_in.DMA_TASK_REG[i].wr_ack = ready_i[i];
        end
    end
endgenerate

kdma_decoder_am u_kdma_decoder_am (
    .clk      (clk     ),
    .arst_n   (rst_n   ),

    .s_apb    (apb_if  ),

    .hwif_in  (hwif_in ),
    .hwif_out (hwif_out)
);

    
endmodule