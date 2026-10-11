import kdma_user_am_pkg::*;

module kdma_user_flatten #(
    parameter DMA_CHANNEL_COUNT = 8
) (
    input  logic                         clk          ,
    input  logic                         rst_n        ,

    input  logic                         bar_psel_i   ,
    input  logic                         bar_penable_i,
    output logic                         bar_pready_o ,
    input  logic [63:0]                  bar_paddr_i  ,
    input  logic                         bar_pwrite_i ,
    input  logic [127:0]                 bar_pwdata_i ,
    input  logic [15:0]                  bar_pstrb_i  ,
    output logic [127:0]                 bar_prdata_o ,

    output logic [DMA_CHANNEL_COUNT-1:0] user_irq_o   
);

    kdma_user_am__out_t hwif_out;

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

    assign user_irq_o[0] = hwif_out.USER_IRQ_QUART_REG[0].IRQ_CONTROL_0.value;
    assign user_irq_o[1] = hwif_out.USER_IRQ_QUART_REG[0].IRQ_CONTROL_1.value;
    assign user_irq_o[2] = hwif_out.USER_IRQ_QUART_REG[0].IRQ_CONTROL_2.value;
    assign user_irq_o[3] = hwif_out.USER_IRQ_QUART_REG[0].IRQ_CONTROL_3.value;
    assign user_irq_o[4] = hwif_out.USER_IRQ_QUART_REG[1].IRQ_CONTROL_0.value;
    assign user_irq_o[5] = hwif_out.USER_IRQ_QUART_REG[1].IRQ_CONTROL_1.value;
    assign user_irq_o[6] = hwif_out.USER_IRQ_QUART_REG[1].IRQ_CONTROL_2.value;
    assign user_irq_o[7] = hwif_out.USER_IRQ_QUART_REG[1].IRQ_CONTROL_3.value;

    kdma_user_am u_kdma_user_am (
        .clk      (clk     ),
        .arst_n   (rst_n   ),

        .s_apb    (apb_if  ),

        .hwif_out (hwif_out)
    );

endmodule