module kdma_pcie_destraddle (
    input  logic         clk                 ,
    input  logic         rst_n               ,

    input  logic         pcie_valid_i        ,
    output logic         pcie_ready_o        ,
    input  logic [127:0] pcie_data_i         ,
    input  logic [4:0]   pcie_sof_i          ,
    input  logic [4:0]   pcie_eof_i          ,
    input  logic [7:0]   pcie_bar_hit_i      ,

    output logic         pcie_destr_valid_o  ,
    input  logic         pcie_destr_ready_i  ,
    output logic [127:0] pcie_destr_data_o   ,
    output logic [7:0]   pcie_destr_bar_hit_o,
    output logic [4:0]   pcie_destr_eof_o    
);

    typedef enum logic [1:0] { 
        AWAIT_HEADER  ,
        NONSTR_NORMAL ,
        NONSTR_HALFWAY,
        STRADDLED     
    } state_t;

    state_t state, state_next;

    logic [63:0] buffer, buffer_next;
    logic flag, flag_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= AWAIT_HEADER;
            buffer <= '{default: '0};
            flag <= '0;
        end
        else begin
            state <= state_next;
            buffer <= buffer_next;
            flag <= flag_next;
        end
    end

    always_comb begin
        state_next = state;
        case (state)
            AWAIT_HEADER: begin
                if (pcie_valid_i && pcie_ready_o) begin
                    if ((pcie_sof_i == 5'b10000) && (pcie_eof_i[4] == '1)) begin
                        state_next = AWAIT_HEADER;
                    end
                    else if ((pcie_sof_i == 5'b10000) && (pcie_eof_i[4] == '0)) begin
                        state_next = NONSTR_NORMAL;
                    end
                    else if ((pcie_sof_i == 5'b11000) && (pcie_eof_i[4] == '0)) begin
                        state_next = NONSTR_HALFWAY;
                    end
                    else begin
                        state_next = AWAIT_HEADER;
                    end
                end
                else begin
                    state_next = AWAIT_HEADER;
                end
            end
            NONSTR_NORMAL, NONSTR_HALFWAY, STRADDLED: begin
                if (pcie_valid_i && pcie_ready_o) begin
                    if ((pcie_eof_i[4] == '1) && (pcie_sof_i[4] == '0)) begin
                        state_next = AWAIT_HEADER;
                    end
                    else if ((pcie_eof_i[4] == '1) && (pcie_sof_i[4] == '1)) begin
                        state_next = STRADDLED;
                    end
                    else begin
                        state_next = state;
                    end
                end
                else begin
                    state_next = state;
                end
            end
            default: state_next = AWAIT_HEADER;
        endcase
    end

    always_comb begin
        buffer_next = buffer;
        flag_next = flag;

        pcie_destr_valid_o   = '0;
        pcie_destr_data_o    = '0;
        pcie_destr_bar_hit_o = '0;
        pcie_destr_eof_o     = '0;

        pcie_ready_o = '0;

        case (state)
            AWAIT_HEADER  : begin
                if (pcie_sof_i == 5'b10000) begin
                    pcie_destr_valid_o   = pcie_valid_i  ;
                    pcie_destr_data_o    = pcie_data_i   ;
                    pcie_destr_bar_hit_o = pcie_bar_hit_i;
                    pcie_destr_eof_o     = pcie_eof_i    ;
                    
                    pcie_ready_o = pcie_destr_ready_i;
                end
                else if (pcie_sof_i == 5'b11000) begin
                    pcie_destr_valid_o   = '0;
                    pcie_destr_data_o    = '0;
                    pcie_destr_bar_hit_o = '0;
                    pcie_destr_eof_o     = '0;
                    
                    pcie_ready_o = '1;

                    buffer_next[63:0] = pcie_data_i[127:64];
                end
            end
            NONSTR_NORMAL : begin
                pcie_destr_valid_o   = pcie_valid_i  ;
                pcie_destr_data_o    = pcie_data_i   ;
                pcie_destr_bar_hit_o = pcie_bar_hit_i;
                pcie_destr_eof_o     = pcie_eof_i    ;
                
                pcie_ready_o = pcie_destr_ready_i;

                if (pcie_sof_i[4] == 1) begin
                    buffer_next = (pcie_valid_i && pcie_ready_o) ? pcie_data_i[127:64] : buffer;
                end
            end
            NONSTR_HALFWAY, STRADDLED: begin
                if (pcie_sof_i[4] == 0) begin
                    if (pcie_eof_i <= 5'b10111) begin
                        pcie_destr_valid_o   = pcie_valid_i                     ;
                        pcie_destr_data_o    = {pcie_data_i[63:0], buffer[63:0]};
                        pcie_destr_bar_hit_o = pcie_bar_hit_i                   ;
                        pcie_destr_eof_o     = pcie_eof_i | 4'h8                ;
                        
                        pcie_ready_o = pcie_destr_ready_i;

                        buffer_next = (pcie_valid_i && pcie_ready_o) ? pcie_data_i[127:64] : buffer;
                    end
                    else begin
                        pcie_destr_valid_o   = pcie_valid_i                                  ;
                        pcie_destr_data_o    = {pcie_data_i[63:0], buffer[63:0]}             ;
                        pcie_destr_bar_hit_o = pcie_bar_hit_i                                ;
                        pcie_destr_eof_o     = flag ? 5'h10 | 5'(pcie_eof_i[3:0] & 4'h7) : '0;
                        
                        pcie_ready_o = flag & pcie_destr_ready_i;

                        buffer_next = (pcie_destr_valid_o && pcie_destr_ready_i) ? pcie_data_i[127:64] : buffer;

                        flag_next = pcie_destr_valid_o && pcie_destr_ready_i ? ~flag : flag;
                    end
                end
                else begin
                    pcie_destr_valid_o   = pcie_valid_i                     ;
                    pcie_destr_data_o    = {pcie_data_i[63:0], buffer[63:0]};
                    pcie_destr_bar_hit_o = pcie_bar_hit_i                   ;
                    pcie_destr_eof_o     = pcie_eof_i | 4'h8                ;
                    
                    pcie_ready_o = pcie_destr_ready_i;

                    buffer_next = (pcie_valid_i && pcie_ready_o) ? pcie_data_i[127:64] : buffer;
                end
            end
            default: begin
            end
        endcase
    end
    
endmodule
