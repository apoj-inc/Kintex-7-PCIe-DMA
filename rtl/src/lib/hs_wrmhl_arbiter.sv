module hs_wrmhl_arbiter #(
    parameter DATA_WIDTH = 32,
    parameter INPUT_NUM  = 5 ,

    parameter ADDR_WIDTH = INPUT_NUM == 1 ? 1 : $clog2(INPUT_NUM)
) (
    input  logic                  clk                ,
    input  logic                  rst_n              ,

    input  logic [INPUT_NUM-1:0]  valid_i            ,
    output logic [INPUT_NUM-1:0]  ready_o            ,
    input  logic [DATA_WIDTH-1:0] data_i  [INPUT_NUM],
    input  logic [INPUT_NUM-1:0]  last_i             ,

    output logic                  valid_o            ,
    input  logic                  ready_i            ,
    output logic [DATA_WIDTH-1:0] data_o             ,
    output logic                  last_o             ,

    output logic [ADDR_WIDTH-1:0] sel_o              
);

    logic idle, idle_next;

    logic [ADDR_WIDTH-1:0] sel, sel_next;
    logic [INPUT_NUM*2-1:0] valid_i_shifted;
    logic [ADDR_WIDTH-1:0] increment;

    assign ready_o = ready_i << sel;
    assign valid_o = valid_i[sel]  ;
    assign data_o  = data_i[sel]   ;
    assign last_o  = last_i[sel]   ;

    assign sel_o = sel;

    assign valid_i_shifted = {valid_i, valid_i} >> sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel <= '0;
            idle <= '1;
        end
        else begin
            sel <= sel_next;
            idle <= idle_next;
        end
    end

    always_comb begin
        sel_next = sel;
        idle_next = idle;
        increment = 0;

        if (valid_o && ready_i) begin
            if (last_o) begin
                for (int i = INPUT_NUM-1; i > 0; i--) begin
                    if (valid_i_shifted[i]) begin
                        increment = i;
                    end
                end
                
                sel_next = (sel_next + increment) >= INPUT_NUM ? (sel_next + increment - INPUT_NUM) : (sel_next + increment);
                
                idle_next = '1;
            end
            else begin
                idle_next = '0;
            end
        end
        else if (!valid_o) begin
            if (idle) begin
                for (int i = INPUT_NUM-1; i > 0; i--) begin
                    if (valid_i_shifted[i]) begin
                        increment = i;
                    end
                end
                
                sel_next = (sel_next + increment) >= INPUT_NUM ? (sel_next + increment - INPUT_NUM) : (sel_next + increment);
            end
        end
    end

endmodule
