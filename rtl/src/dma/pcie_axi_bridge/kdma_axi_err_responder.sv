module kdma_axi_err_responder #(
    parameter AXI_DATA_WIDTH = 128,
    parameter AXI_ID_WIDTH   = 4  
) (
    input  logic                         clk        ,
    input  logic                         rst_n      ,

    input  logic                         err_valid_i,
    output logic                         err_ready_o,
    input  logic [AXI_ID_WIDTH-1:0]      err_id_i   ,
    input  logic [7:0]                   err_len_i  ,

    output logic                         rvalid_o   ,
    input  logic                         rready_i   ,
    output logic [AXI_DATA_WIDTH-1:0]    rdata_o    ,
    output logic                         rlast_o    ,
    output logic [2:0]                   rresp_o    ,
    output logic [AXI_ID_WIDTH-1:0]      rid_o      
);

    logic [7:0] count;

    assign rresp_o = 3'b010; // slverr
    assign rdata_o = '0;
    assign rlast_o = (count == 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_ready_o <= '0;
        end
        else begin
            if (err_valid_i && err_ready_o) begin
                err_ready_o <= '0;
            end
            else if (rvalid_o == '0) begin
                err_ready_o <= '1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_o <= '0;
            rid_o    <= '0;
            count    <= '0;
        end
        else begin
            if (err_valid_i && err_ready_o) begin
                rvalid_o <= '1;
                rid_o    <= err_id_i;
                count    <= err_len_i;
            end
            else if (rvalid_o && rready_i) begin
                count <= (count == 0) ? 0 : (count - 1);
                if (rlast_o) begin
                    rvalid_o <= '0;
                end
            end
        end
    end
    
endmodule