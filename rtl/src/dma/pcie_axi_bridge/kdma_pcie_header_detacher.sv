module kdma_pcie_header_detacher (
    input  logic         clk                  ,
    input  logic         rst_n                ,

    input  logic         pcie_destr_valid_i   ,
    output logic         pcie_destr_ready_o   ,
    input  logic [127:0] pcie_destr_data_i    ,
    input  logic [7:0]   pcie_destr_bar_hit_i ,
    input  logic [4:0]   pcie_destr_eof_i     ,

    output logic         pcie_detach_valid_o  ,
    input  logic         pcie_detach_ready_i  ,
    output logic [127:0] pcie_detach_data_o   ,
    output logic         pcie_detach_header_o ,
    output logic [7:0]   pcie_detach_bar_hit_o,
    output logic [4:0]   pcie_detach_eof_o    
);

    typedef enum logic [1:0] {
        AWAIT_HEADER,
        ADDRESS_32  ,
        ADDRESS_64  
    } state_t;

    state_t state, state_next;

    logic [31:0] buffer, buffer_next;
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
                if (pcie_detach_valid_o && pcie_detach_ready_i) begin
                    if (pcie_destr_eof_i == 5'b11011) begin
                        state_next = AWAIT_HEADER; // 3dw header no data
                    end
                    else if (pcie_destr_eof_i == 5'b11111) begin
                        if (pcie_destr_data_i[29] == '0) begin
                            state_next = ADDRESS_32; // 3dw header 1dw data
                        end
                        else begin
                            state_next = AWAIT_HEADER; // 4dw header no data
                        end
                    end
                    else begin
                        if (pcie_destr_data_i[29] == '0) begin
                            state_next = ADDRESS_32; // 3dw header more data
                        end
                        else begin
                            state_next = ADDRESS_64; // 4dw header more data
                        end
                    end
                end
            end
            ADDRESS_32, ADDRESS_64: begin
                if (pcie_detach_valid_o && pcie_detach_ready_i) begin
                    if (pcie_detach_eof_o[4]) begin
                        state_next = AWAIT_HEADER;
                    end
                    else begin
                        state_next = state;
                    end
                end
                else begin
                    state_next = state;
                end
            end
            default     : begin
            end
        endcase
    end

    always_comb begin
        buffer_next = buffer;
        flag_next   = flag  ;

        pcie_destr_ready_o = '0;

        pcie_detach_valid_o   = '0;
        pcie_detach_data_o    = '0;
        pcie_detach_header_o  = '0;
        pcie_detach_bar_hit_o = '0;
        pcie_detach_eof_o     = '0;

        case (state)
            AWAIT_HEADER: begin

                pcie_detach_valid_o   = pcie_destr_valid_i  ;
                pcie_detach_data_o    = pcie_destr_data_i   ;
                pcie_detach_header_o  = '1                  ;
                pcie_detach_bar_hit_o = pcie_destr_bar_hit_i;
                pcie_detach_eof_o     = pcie_destr_eof_i    ;

                if (pcie_destr_data_i[29] == '0) begin
                    buffer_next = pcie_destr_data_i[127:96];

                    if (pcie_destr_eof_i == 5'b11111) begin
                        pcie_destr_ready_o = '0;
                        pcie_detach_eof_o  = '0;
                        
                        flag_next = pcie_detach_valid_o && pcie_detach_ready_i ? ~flag : flag;
                    end
                    else begin
                        pcie_destr_ready_o = pcie_detach_ready_i;
                        pcie_destr_ready_o = pcie_detach_ready_i;
                    end
                end
                else begin
                    pcie_detach_eof_o  = pcie_destr_eof_i   ;
                    pcie_destr_ready_o = pcie_detach_ready_i;
                end
            end
            ADDRESS_32  : begin
                if (pcie_destr_eof_i <= 5'b11011) begin
                    pcie_destr_ready_o = pcie_detach_ready_i;

                    pcie_detach_valid_o   = pcie_destr_valid_i                                    ;
                    pcie_detach_data_o    = {pcie_destr_data_i[95:0], buffer}                     ;
                    pcie_detach_header_o  = '0                                                    ;
                    pcie_detach_bar_hit_o = pcie_destr_bar_hit_i                                  ;
                    pcie_detach_eof_o     = {pcie_destr_eof_i[4], 4'(pcie_destr_eof_i + 'h4)};

                    buffer_next = (pcie_destr_valid_i && pcie_destr_ready_o) ? pcie_destr_data_i[127:96] : buffer;
                end
                else begin
                    pcie_destr_ready_o = flag & pcie_detach_ready_i;

                    pcie_detach_valid_o   = pcie_destr_valid_i               ;
                    pcie_detach_data_o    = {pcie_destr_data_i[95:0], buffer};
                    pcie_detach_header_o  = '0                               ;
                    pcie_detach_bar_hit_o = pcie_destr_bar_hit_i             ;
                    pcie_detach_eof_o     = flag ? 5'b10011 : '0             ;

                    buffer_next = (pcie_detach_valid_o && pcie_detach_ready_i) ? pcie_destr_data_i[127:96] : buffer;

                    flag_next = pcie_detach_valid_o && pcie_detach_ready_i ? ~flag : flag;
                end
            end
            ADDRESS_64  : begin
                pcie_destr_ready_o = pcie_detach_ready_i;

                pcie_detach_valid_o   = pcie_destr_valid_i  ;
                pcie_detach_data_o    = pcie_destr_data_i   ;
                pcie_detach_header_o  = '0                  ;
                pcie_detach_bar_hit_o = pcie_destr_bar_hit_i;
                pcie_detach_eof_o     = pcie_destr_eof_i    ;
            end
            default     : begin
                
            end
        endcase
    end
    
endmodule
