import kdma_pcie_headers_pkg::*;

module kdma_pcie_tlp_decoder #(
    parameter BAR_COUNT         = 6,

    parameter DMA_CHANNEL_COUNT = 8,
    parameter PIPELINE_CAPACITY = 4,

    parameter TOTAL_ID_COUNT = DMA_CHANNEL_COUNT * PIPELINE_CAPACITY
) (
    input  logic                      clk                              ,
    input  logic                      rst_n                            ,

    input  logic                      pcie_detach_valid_i              ,
    output logic                      pcie_detach_ready_o              ,
    input  logic [127:0]              pcie_detach_data_i               ,
    input  logic                      pcie_detach_header_i             ,
    input  logic [7:0]                pcie_detach_bar_hit_i            ,
    input  logic [4:0]                pcie_detach_eof_i                ,

    output logic [BAR_COUNT-1:0]      bar_psel_o                       ,
    output logic                      bar_penable_o                    ,
    input  logic [BAR_COUNT-1:0]      bar_pready_i                     ,
    output logic [63:0]               bar_paddr_o                      ,
    output logic                      bar_pwrite_o                     ,
    output logic [127:0]              bar_pwdata_o                     ,
    output logic [15:0]               bar_pstrb_o                      ,
    input  logic [127:0]              bar_prdata_i          [BAR_COUNT],

    output logic [TOTAL_ID_COUNT-1:0] dmard_valid_o                    ,
    input  logic [TOTAL_ID_COUNT-1:0] dmard_ready_i                    ,
    output logic [127:0]              dmard_data_o                     ,
    output logic                      dmard_last_o                     ,

    output logic                      pcie_valid_o                     ,
    input  logic                      pcie_ready_i                     ,
    output logic [127:0]              pcie_data_o                      ,
    output logic [15:0]               pcie_tkeep_o                     ,

    input  logic [7:0]                bus_number_i                     ,
    input  logic [4:0]                device_number_i                  ,
    input  logic [2:0]                function_number_i                ,

    output logic                      error_o                          
);

    logic [31:0] calc;

    typedef enum logic[2:0] {
        AWAIT_HEADER,
        UNSUPPORTED ,
        ABORT       ,
        BAR_READ    ,
        BAR_RD_RESP ,
        BAR_WRITE   ,
        DMA_READ    
    } state_t;

    state_t state, state_next;

    logic [31:0]  cnt, cnt_next;

    logic [31:0] kal;

    logic [15:0]  req_id_saved  , req_id_saved_next  ;
    logic [7:0]   tag_saved     , tag_saved_next     ;
    logic [9:0]   length_saved  , length_saved_next  ;
    logic [1:0]   addr_qw_saved , addr_qw_saved_next ;
    logic [1:0]   addr_lo_saved , addr_lo_saved_next ;
    logic [7:0]   bar_hit_saved , bar_hit_saved_next ;
    logic [11:0]  byte_cnt_saved, byte_cnt_saved_next;
    logic [127:0] cpl_data      , cpl_data_next      ;
    logic         error         , error_next         ;
    assign error_o = error;

    logic cpl_sent    , cpl_sent_next    ;
    logic trigger_last, trigger_last_next;

    logic [BAR_COUNT-1:0] bar_psel   , bar_psel_next   ;
    logic                 bar_penable, bar_penable_next;
    logic [63:0]          bar_paddr  , bar_paddr_next  ;
    logic                 bar_pwrite , bar_pwrite_next ;
    logic [127:0]         bar_pwdata , bar_pwdata_next ;
    logic [15:0]          bar_pstrb  , bar_pstrb_next  ;
    assign bar_psel_o    = bar_psel   ;
    assign bar_penable_o = bar_penable;
    assign bar_paddr_o   = bar_paddr  ;
    assign bar_pwrite_o  = bar_pwrite ;
    assign bar_pwdata_o  = bar_pwdata ;
    assign bar_pstrb_o   = bar_pstrb  ;

    header_dw0_t             h_dw0_inb     , h_dw0_outb     ;
    memory_request_3dw_12_t  mr_3dw_12_inb , mr_3dw_12_outb ;
    memory_request_4dw_123_t mr_4dw_123_inb, mr_4dw_123_outb;
    cpl_3dw_12_t             cpl_3dw_12_inb, cpl_3dw_12_outb;
    assign h_dw0_inb      = pcie_detach_data_i[0  +: 32];
    assign mr_3dw_12_inb  = pcie_detach_data_i[32 +: 64];
    assign mr_4dw_123_inb = pcie_detach_data_i[32 +: 96];
    assign cpl_3dw_12_inb = pcie_detach_data_i[32 +: 64];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= AWAIT_HEADER;

            cnt <= '0;

            req_id_saved   <= '0          ;
            tag_saved      <= '0          ;
            length_saved   <= '0          ;
            addr_qw_saved  <= '0          ;
            addr_lo_saved  <= '0          ;
            bar_hit_saved  <= '0          ;
            byte_cnt_saved <= '0          ;
            cpl_data       <= '0          ;
            error          <= '0          ;

            cpl_sent     <= '0;
            trigger_last <= '0;

            bar_psel    <= '0;
            bar_penable <= '0;
            bar_paddr   <= '0;
            bar_pwrite  <= '0;
            bar_pwdata  <= '0;
            bar_pstrb   <= '0;
        end
        else begin
            state <= state_next;

            cnt <= cnt_next;

            req_id_saved   <= req_id_saved_next  ;
            tag_saved      <= tag_saved_next     ;
            length_saved   <= length_saved_next  ;
            addr_qw_saved  <= addr_qw_saved_next ;
            addr_lo_saved  <= addr_lo_saved_next ;
            bar_hit_saved  <= bar_hit_saved_next ;
            byte_cnt_saved <= byte_cnt_saved_next;
            cpl_data       <= cpl_data_next      ;
            error          <= error_next         ;
            
            cpl_sent     <= cpl_sent_next    ;
            trigger_last <= trigger_last_next;
            
            bar_psel    <= bar_psel_next   ;
            bar_penable <= bar_penable_next;
            bar_paddr   <= bar_paddr_next  ;
            bar_pwrite  <= bar_pwrite_next ;
            bar_pwdata  <= bar_pwdata_next ;
            bar_pstrb   <= bar_pstrb_next  ;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            AWAIT_HEADER: begin
                if (pcie_detach_valid_i && pcie_detach_ready_o) begin
                    if (pcie_detach_header_i) begin
                        case ({h_dw0_inb.fmt, h_dw0_inb.tp})
                            RD_32, RD_64: begin
                                if (h_dw0_inb.length > (4 - (({h_dw0_inb.fmt, h_dw0_inb.tp} == RD_32) ? (mr_3dw_12_inb.addr[1:0]) : (mr_4dw_123_inb.addr_lo[1:0])))) begin
                                    state_next = ABORT;
                                end
                                else begin
                                    state_next = BAR_READ;
                                end
                            end
                            WR_32, WR_64: begin
                                if (h_dw0_inb.length > (4 - (({h_dw0_inb.fmt, h_dw0_inb.tp} == WR_32) ? (mr_3dw_12_inb.addr[1:0]) : (mr_4dw_123_inb.addr_lo[1:0])))) begin
                                    state_next = ABORT;
                                end
                                else if (mr_3dw_12_inb.fdw_be != 4'b1111) begin
                                    state_next = ABORT;
                                end
                                else if (mr_3dw_12_inb.ldw_be != 4'b1111 && mr_3dw_12_inb.ldw_be != 4'b0000) begin
                                    state_next = ABORT;
                                end
                                else begin
                                    state_next = BAR_WRITE;
                                end
                            end
                            CPL    : begin
                                state_next = AWAIT_HEADER;
                            end
                            CPLD   : begin
                                state_next = DMA_READ;
                            end
                            default: begin
                                state_next = UNSUPPORTED;
                            end 
                        endcase
                    end
                    else begin
                        state_next = AWAIT_HEADER;
                    end
                end
            end
            UNSUPPORTED, ABORT: begin
                if (cpl_sent) begin
                    if (pcie_detach_valid_i && pcie_detach_header_i) begin
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
            BAR_READ    : begin
                if (bar_penable_o && |(bar_pready_i & bar_psel_o)) begin
                    state_next = BAR_RD_RESP;
                end
                else begin
                    state_next = BAR_READ;
                end
            end
            BAR_WRITE   : begin
                if (bar_penable_o && |(bar_pready_i & bar_psel_o)) begin
                    state_next = AWAIT_HEADER;
                end
                else begin
                    state_next = BAR_WRITE;
                end
            end
            BAR_RD_RESP : begin
                if (cpl_sent) begin
                    state_next = AWAIT_HEADER;
                end
                else begin
                    state_next = BAR_RD_RESP;
                end
            end
            DMA_READ    : begin
                if (pcie_detach_valid_i && pcie_detach_ready_o && pcie_detach_eof_i[4]) begin
                    state_next = AWAIT_HEADER;
                end
                else begin
                    state_next = DMA_READ;
                end
            end
            default     : begin
                state_next = AWAIT_HEADER;
            end
        endcase
    end

    always_comb begin
        calc = 0;
        pcie_detach_ready_o = '0;

        pcie_valid_o = '0;
        pcie_data_o  = '0;
        pcie_tkeep_o = '0;

        cnt_next = cnt;

        req_id_saved_next   = req_id_saved  ;
        tag_saved_next      = tag_saved     ;
        length_saved_next   = length_saved  ;
        addr_qw_saved_next  = addr_qw_saved ;
        addr_lo_saved_next  = addr_lo_saved ;
        bar_hit_saved_next  = bar_hit_saved ;
        byte_cnt_saved_next = byte_cnt_saved;
        cpl_data_next       = cpl_data      ;
        error_next          = error         ;

        cpl_sent_next = cpl_sent;

        bar_psel_next    = bar_psel   ;
        bar_penable_next = bar_penable;
        bar_paddr_next   = bar_paddr  ;
        bar_pwrite_next  = bar_pwrite ;
        bar_pwdata_next  = bar_pwdata ;
        bar_pstrb_next   = bar_pstrb  ;

        h_dw0_outb      = '0;
        mr_3dw_12_outb  = '0;
        mr_4dw_123_outb = '0;
        cpl_3dw_12_outb = '0;

        case (state)
            AWAIT_HEADER: begin
                pcie_detach_ready_o = '1;

                if (pcie_detach_valid_i && pcie_detach_ready_o) begin
                    if (pcie_detach_header_i) begin
                        case ({h_dw0_inb.fmt, h_dw0_inb.tp})
                            RD_32, WR_32: begin
                                req_id_saved_next = mr_3dw_12_inb.req_id;
                                tag_saved_next = mr_3dw_12_inb.tag;
                                length_saved_next = h_dw0_inb.length;
                                addr_qw_saved_next = mr_3dw_12_inb.addr[1:0];
                                
                                casez (mr_3dw_12_inb.fdw_be)
                                    4'b0000: addr_lo_saved_next = 2'b00;
                                    4'b???1: addr_lo_saved_next = 2'b00;
                                    4'b??10: addr_lo_saved_next = 2'b01;
                                    4'b?100: addr_lo_saved_next = 2'b10;
                                    4'b1000: addr_lo_saved_next = 2'b11;
                                endcase

                                if (mr_3dw_12_inb.ldw_be == '0) begin
                                    casez (mr_3dw_12_inb.fdw_be)
                                        4'b1??1: byte_cnt_saved_next = 4;
                                        4'b01?1: byte_cnt_saved_next = 3;
                                        4'b1?10: byte_cnt_saved_next = 3;
                                        4'b0011: byte_cnt_saved_next = 2;
                                        4'b0110: byte_cnt_saved_next = 2;
                                        4'b1100: byte_cnt_saved_next = 2;
                                        4'b0001: byte_cnt_saved_next = 1;
                                        4'b0010: byte_cnt_saved_next = 1;
                                        4'b0100: byte_cnt_saved_next = 1;
                                        4'b1000: byte_cnt_saved_next = 1;
                                        4'b0000: byte_cnt_saved_next = 1;
                                    endcase
                                end
                                else begin
                                    byte_cnt_saved_next = (h_dw0_inb.length << 2);

                                    casez (mr_3dw_12_inb.fdw_be)
                                        4'b???1: byte_cnt_saved_next = byte_cnt_saved_next - 0;
                                        4'b??10: byte_cnt_saved_next = byte_cnt_saved_next - 1;
                                        4'b?100: byte_cnt_saved_next = byte_cnt_saved_next - 2;
                                        4'b1000: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                        4'b0000: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                    endcase

                                    casez (mr_3dw_12_inb.ldw_be)
                                        4'b1???: byte_cnt_saved_next = byte_cnt_saved_next - 0;
                                        4'b01??: byte_cnt_saved_next = byte_cnt_saved_next - 1;
                                        4'b001?: byte_cnt_saved_next = byte_cnt_saved_next - 2;
                                        4'b0001: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                        4'b0000: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                    endcase
                                end

                                bar_hit_saved_next = pcie_detach_bar_hit_i;
           
                                bar_psel_next     = {h_dw0_inb.fmt, h_dw0_inb.tp} == RD_32 ? pcie_detach_bar_hit_i : '0;
                                bar_paddr_next    = {32'h0, mr_3dw_12_inb.addr[29:2], 4'h0};
                                bar_pstrb_next    = h_dw0_inb.length == 4 ? 16'hFFFF << {mr_3dw_12_inb.addr[1:0], 2'b0} :
                                                    h_dw0_inb.length == 3 ? 16'h0FFF << {mr_3dw_12_inb.addr[1:0], 2'b0} :
                                                    h_dw0_inb.length == 2 ? 16'h00FF << {mr_3dw_12_inb.addr[1:0], 2'b0} :
                                                    h_dw0_inb.length == 1 ? 16'h000F << {mr_3dw_12_inb.addr[1:0], 2'b0} : '1;
                            end
                            RD_64, WR_64: begin
                                req_id_saved_next = mr_4dw_123_inb.req_id;
                                tag_saved_next = mr_4dw_123_inb.tag;
                                length_saved_next = h_dw0_inb.length;
                                addr_qw_saved_next = mr_4dw_123_inb.addr_lo[1:0];
                                
                                casez (mr_4dw_123_inb.fdw_be)
                                    4'b0000: addr_lo_saved_next = 2'b00;
                                    4'b???1: addr_lo_saved_next = 2'b00;
                                    4'b??10: addr_lo_saved_next = 2'b01;
                                    4'b?100: addr_lo_saved_next = 2'b10;
                                    4'b1000: addr_lo_saved_next = 2'b11;
                                endcase

                                if (mr_4dw_123_inb.ldw_be == '0) begin
                                    casez (mr_4dw_123_inb.fdw_be)
                                        4'b1??1: byte_cnt_saved_next = 4;
                                        4'b01?1: byte_cnt_saved_next = 3;
                                        4'b1?10: byte_cnt_saved_next = 3;
                                        4'b0011: byte_cnt_saved_next = 2;
                                        4'b0110: byte_cnt_saved_next = 2;
                                        4'b1100: byte_cnt_saved_next = 2;
                                        4'b0001: byte_cnt_saved_next = 1;
                                        4'b0010: byte_cnt_saved_next = 1;
                                        4'b0100: byte_cnt_saved_next = 1;
                                        4'b1000: byte_cnt_saved_next = 1;
                                        4'b0000: byte_cnt_saved_next = 1;
                                    endcase
                                end
                                else begin
                                    byte_cnt_saved_next = (h_dw0_inb.length << 2);

                                    casez (mr_4dw_123_inb.fdw_be)
                                        4'b???1: byte_cnt_saved_next = byte_cnt_saved_next - 0;
                                        4'b??10: byte_cnt_saved_next = byte_cnt_saved_next - 1;
                                        4'b?100: byte_cnt_saved_next = byte_cnt_saved_next - 2;
                                        4'b1000: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                        4'b0000: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                    endcase

                                    casez (mr_4dw_123_inb.ldw_be)
                                        4'b1???: byte_cnt_saved_next = byte_cnt_saved_next - 0;
                                        4'b01??: byte_cnt_saved_next = byte_cnt_saved_next - 1;
                                        4'b001?: byte_cnt_saved_next = byte_cnt_saved_next - 2;
                                        4'b0001: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                        4'b0000: byte_cnt_saved_next = byte_cnt_saved_next - 3;
                                    endcase
                                end

                                bar_hit_saved_next = pcie_detach_bar_hit_i;
                                
                                bar_psel_next     = {h_dw0_inb.fmt, h_dw0_inb.tp} == RD_64 ? pcie_detach_bar_hit_i : '0;
                                bar_paddr_next    = {32'h0, mr_4dw_123_inb.addr_lo[29:2], 4'h0};
                                bar_pstrb_next    = h_dw0_inb.length == 4 ? 16'hFFFF << {mr_4dw_123_inb.addr_lo[1:0], 2'b0} :
                                                    h_dw0_inb.length == 3 ? 16'h0FFF << {mr_4dw_123_inb.addr_lo[1:0], 2'b0} :
                                                    h_dw0_inb.length == 2 ? 16'h00FF << {mr_4dw_123_inb.addr_lo[1:0], 2'b0} :
                                                    h_dw0_inb.length == 1 ? 16'h000F << {mr_4dw_123_inb.addr_lo[1:0], 2'b0} : '1;
                            end
                            CPL    : begin
                                error_next = '1;
                            end
                            CPLD   : begin
                                tag_saved_next = cpl_3dw_12_inb.tag;
                                byte_cnt_saved_next = cpl_3dw_12_inb.byte_cnt;

                                trigger_last_next = ((h_dw0_inb.length << 2) == (cpl_3dw_12_inb.byte_cnt));
                            end
                            default: begin
                                req_id_saved_next = mr_4dw_123_inb.req_id;
                                tag_saved_next = mr_4dw_123_inb.tag;
                            end
                        endcase
                    end
                end
            end
            UNSUPPORTED, ABORT: begin
                if (pcie_detach_valid_i) begin
                    if (pcie_detach_header_i) begin
                        pcie_detach_ready_o = '0;
                    end
                    else begin
                        pcie_detach_ready_o = '1;
                    end
                end
                else begin
                    pcie_detach_ready_o = '1;
                end

                {h_dw0_outb.rsvd_0, h_dw0_outb.rsvd_1, h_dw0_outb.rsvd_2} = '0;
                {h_dw0_outb.fmt, h_dw0_outb.tp} = CPL;
                h_dw0_outb.qos = '0;
                h_dw0_outb.digest = '0;
                h_dw0_outb.err = '0;
                h_dw0_outb.attr = '0;
                h_dw0_outb.addr_tran = '0;
                h_dw0_outb.length = '0;

                cpl_3dw_12_outb.req_id = req_id_saved;
                cpl_3dw_12_outb.tag = tag_saved;
                cpl_3dw_12_outb.rsvd = '0;
                cpl_3dw_12_outb.addr_lo = addr_lo_saved;
                cpl_3dw_12_outb.cpl_id = {bus_number_i, device_number_i, function_number_i};
                cpl_3dw_12_outb.cpl_sts = (state == UNSUPPORTED) ? STS_UR : STS_CA;
                cpl_3dw_12_outb.bcm = '0;
                cpl_3dw_12_outb.byte_cnt = byte_cnt_saved;

                pcie_data_o = {32'h0, cpl_3dw_12_outb, h_dw0_outb};
                pcie_valid_o = ~cpl_sent;
                pcie_tkeep_o = 16'h0FFF;

                if (cpl_sent == 0) begin
                    cpl_sent_next = pcie_valid_o && pcie_ready_i;
                end
                else begin
                    if (pcie_detach_valid_i && pcie_detach_header_i) begin
                        cpl_sent_next = '0;
                    end
                end
            end
            BAR_READ    : begin
                pcie_detach_ready_o = '0;

                bar_penable_next = '1;

                cpl_data_next = '0;
                for (int i = 0; i < BAR_COUNT; i++) begin
                    if (bar_hit_saved[i] == '1) begin
                        cpl_data_next = cpl_data_next | (bar_pready_i[i] ? bar_prdata_i[i] : '0);
                    end
                end
            end
            BAR_WRITE   : begin
                pcie_detach_ready_o = (bar_penable_o && |(bar_pready_i & bar_psel_o));

                if (pcie_detach_valid_i) begin
                    bar_psel_next    = bar_hit_saved;
                    bar_penable_next = |bar_psel;
                    bar_pwrite_next  = '1;
                    bar_pwdata_next  = pcie_detach_data_i;

                    if (pcie_detach_ready_o) begin
                        bar_psel_next = '0;
                        bar_penable_next = '0;
                    end
                end
                else begin
                    bar_psel_next = '0;
                end
            end
            BAR_RD_RESP : begin
                {h_dw0_outb.rsvd_0, h_dw0_outb.rsvd_1, h_dw0_outb.rsvd_2} = '0;
                {h_dw0_outb.fmt, h_dw0_outb.tp} = CPL;
                h_dw0_outb.qos = '0;
                h_dw0_outb.digest = '0;
                h_dw0_outb.err = '0;
                h_dw0_outb.attr = '0;
                h_dw0_outb.addr_tran = '0;
                h_dw0_outb.length = length_saved;

                cpl_3dw_12_outb.req_id = req_id_saved;
                cpl_3dw_12_outb.tag = tag_saved;
                cpl_3dw_12_outb.rsvd = '0;
                cpl_3dw_12_outb.addr_lo = addr_lo_saved;
                cpl_3dw_12_outb.cpl_id = {bus_number_i, device_number_i, function_number_i};
                cpl_3dw_12_outb.cpl_sts = STS_SC;
                cpl_3dw_12_outb.bcm = '0;
                cpl_3dw_12_outb.byte_cnt = byte_cnt_saved;
                
                pcie_data_o = (cnt == 0) ? {cpl_data[31:0], cpl_3dw_12_outb, h_dw0_outb} : {32'h0, cpl_data[127:32]};
                pcie_valid_o = ~cpl_sent;
                pcie_tkeep_o = (cnt == 0) ? 16'hFFFF : (16'h0FFF >> ((3 - (length_saved - 1)) << 2));

                cnt_next = (pcie_valid_o && pcie_ready_i) ? 1 : cnt;

                if (cpl_sent == 0) begin
                    cpl_sent_next = (length_saved == 1) ? (pcie_valid_o && pcie_ready_i) : (cnt == 1) && (pcie_valid_o && pcie_ready_i);
                end
                else begin
                    cpl_sent_next = '0;
                    cnt_next = '0;
                end
            end
            DMA_READ    : begin
                dmard_valid_o[tag_saved] = pcie_detach_valid_i;
                pcie_detach_ready_o = dmard_ready_i[tag_saved];

                dmard_data_o = pcie_detach_data_i;
                dmard_last_o = trigger_last ? pcie_detach_eof_i[4] : '0;
            end
            default     : begin
                
            end
        endcase
    end
    
endmodule