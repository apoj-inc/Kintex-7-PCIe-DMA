module kdma_aurora_traffic_gen (
    input  logic        clk_i  ,
    input  logic        rstn_i ,

    output logic        valid_o,
    input  logic        ready_i,
    output logic [63:0] data_o 
);

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            valid_o <= '0;
            data_o  <= '0;
        end
        else begin
            valid_o <= '1;
            data_o <= data_o + (valid_o & ready_i);
        end
    end
    
endmodule