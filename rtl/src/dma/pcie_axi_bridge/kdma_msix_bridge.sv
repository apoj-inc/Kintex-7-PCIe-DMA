import kdma_pcie_headers_pkg::*;

module kdma_msix_bridge #(
    parameter PIPELINE_CAPACITY = 4,

    parameter AXI_ID_WIDTH = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)
) (
    input  logic                    clk              ,
    input  logic                    rst_n            ,

    input  logic                    msix_awvalid_i   ,
    output logic                    msix_awready_o   ,
    input  logic [63:0]             msix_awaddr_i    ,
    input  logic [7:0]              msix_awlen_i     ,
    input  logic [AXI_ID_WIDTH-1:0] msix_awid_i      ,
    input  logic [1:0]              msix_awburst_i   ,
    input  logic [2:0]              msix_awsize_i    ,

    input  logic                    msix_wvalid_i    ,
    output logic                    msix_wready_o    ,
    input  logic [127:0]            msix_wdata_i     ,
    input  logic                    msix_wlast_i     ,
    input  logic [15:0]             msix_wstrb_i     ,

    output logic                    msix_bvalid_o    ,
    input  logic                    msix_bready_i    ,
    output logic [AXI_ID_WIDTH-1:0] msix_bid_o       ,
    output logic [1:0]              msix_bresp_o     ,

    output logic                    pcie_valid_o     ,
    input  logic                    pcie_ready_i     ,
    output logic [127:0]            pcie_data_o      ,
    output logic [15:0]             pcie_tkeep_o     ,
    output logic                    pcie_tlast_o     ,

    input  logic [7:0]              bus_number_i     ,
    input  logic [4:0]              device_number_i  ,
    input  logic [2:0]              function_number_i
);

    typedef enum logic [1:0] {
        IDLE    ,
        DATA    ,
        MSIX    ,
        ERR_RESP
    } state_t;

    state_t state, state_next;

    header_dw0_t             hdw0;
    memory_request_3dw_12_t  mr3d;
    memory_request_4dw_123_t mr4d;

    logic [AXI_ID_WIDTH-1:0] bid, bid_next;

    logic wlast_was, wlast_was_next;
    logic b_was    , b_was_next    ;
    logic pcie_was , pcie_was_next ;
    logic hdr_was  , hdr_was_next  ;

    logic [63:0] address, address_next;
    logic [31:0] data   , data_next   ;

    assign msix_bid_o = bid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;

            bid <= '0;

            wlast_was <= '0;
            b_was     <= '0;
            pcie_was  <= '0;
            hdr_was   <= '0;

            address <= '0;
            data    <= '0;
        end
        else begin
            state <= state_next;

            bid <= bid_next;

            wlast_was <= wlast_was_next;
            b_was     <= b_was_next    ;
            pcie_was  <= pcie_was_next ;
            hdr_was   <= hdr_was_next  ;

            address <= address_next;
            data    <= data_next   ;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            IDLE    : begin
                if (msix_awvalid_i && msix_awready_o) begin
                    if (msix_awlen_i == 0) begin
                        state_next = DATA;
                    end
                    else begin
                        state_next = ERR_RESP;
                    end
                end
                else begin
                    state_next = IDLE;
                end
            end
            DATA    : begin
                if (msix_wvalid_i && msix_wready_o) begin
                    case (msix_wstrb_i)
                        'h000F, 'h00F0, 'h0F00, 'hF000: begin
                            state_next = MSIX;
                        end
                        default: begin
                            state_next = ERR_RESP;
                        end
                    endcase
                end
                else begin
                    state_next = DATA;
                end
            end
            MSIX    : begin
                if (b_was && pcie_was) begin
                    state_next = IDLE;
                end
                else begin
                    state_next = MSIX;
                end
            end
            ERR_RESP: begin
                if (msix_bvalid_o && msix_bready_i) begin
                    state_next = IDLE;
                end
                else begin
                    state_next = ERR_RESP;
                end
            end
            default : begin
                state_next = IDLE;
            end
        endcase
    end

    always_comb begin
        msix_awready_o = '0;
        msix_wready_o  = '0;
        msix_bvalid_o  = '0;

        pcie_valid_o = '0;
        pcie_data_o  = '0;
        pcie_tkeep_o = '0;
        pcie_tlast_o = '0;

        hdw0 = '0;
        mr3d = '0;
        mr4d = '0;
        
        bid_next = bid;

        wlast_was_next = wlast_was;
        b_was_next     = b_was    ;
        pcie_was_next  = pcie_was ;
        hdr_was_next   = hdr_was  ;

        address_next = address;

        case (state)
            IDLE    : begin
                msix_awready_o = '1;

                if (msix_awvalid_i && msix_awready_o) begin
                    bid_next = msix_awid_i;
                    address_next = msix_awaddr_i;
                end
            end
            DATA    : begin
                msix_wready_o = '1;

                if (msix_wvalid_i && msix_wready_o) begin
                    if (msix_wlast_i) begin
                        wlast_was_next = '1;
                    end

                    case (msix_wstrb_i)
                        'h000F : begin 
                            address_next = {address[63:4], 4'h0};
                            data_next = msix_wdata_i[31:0];
                        end
                        'h00F0 : begin 
                            address_next = {address[63:4], 4'h4};
                            data_next = msix_wdata_i[63:32];
                        end
                        'h0F00 : begin 
                            address_next = {address[63:4], 4'h8};
                            data_next = msix_wdata_i[95:64];
                        end
                        'hF000 : begin 
                            address_next = {address[63:4], 4'hC};
                            data_next = msix_wdata_i[127:96];
                        end
                        default: begin 
                            address_next = {address[63:4], 4'h0};
                            data_next = msix_wdata_i[31:0];
                        end
                    endcase
                end
            end
            MSIX    : begin
                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.qos, hdw0.rsvd_0, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                hdw0.length = 'h1;

                if (msix_awaddr_i[63:32] == '0) begin
                    {hdw0.fmt, hdw0.tp} = WR_32;
                    {mr3d.addr, mr3d.rsvd} = address[31:0];
                    mr3d.req_id = {bus_number_i, device_number_i, function_number_i};
                    mr3d.tag    = '0;
                    mr3d.ldw_be = '0;
                    mr3d.fdw_be = '1;

                    pcie_valid_o = ~pcie_was         ;
                    pcie_data_o  = {data, mr3d, hdw0};
                    pcie_tkeep_o = 'hFFFF            ;
                    pcie_tlast_o = '1                ;
                end
                else begin
                    {hdw0.fmt, hdw0.tp} = WR_64;
                    {mr4d.addr_hi, mr4d.addr_lo, mr4d.rsvd} = address;
                    mr4d.req_id = {bus_number_i, device_number_i, function_number_i};
                    mr4d.tag    = '0;
                    mr4d.ldw_be = '0;
                    mr4d.fdw_be = '1;

                    pcie_valid_o = ~pcie_was                             ;
                    pcie_data_o  = hdr_was ? {96'h0, data} : {mr4d, hdw0};
                    pcie_tkeep_o = hdr_was ? 'h000F : 'hFFFF             ;
                    pcie_tlast_o = hdr_was                               ;
                end

                if (pcie_valid_o && pcie_ready_i) begin
                    if (pcie_tlast_o) begin
                        pcie_was_next = 1;
                    end
                    else begin
                        hdr_was_next = 1;
                    end
                end

                msix_bvalid_o = ~b_was;
                msix_bresp_o  = 2'b00;

                if (msix_bvalid_o && msix_bready_i) begin
                    b_was_next = 1;
                end

                if (pcie_was && b_was) begin
                    {wlast_was_next, b_was_next, pcie_was_next, hdr_was_next} = '0;
                end
            end
            ERR_RESP: begin
                msix_bvalid_o = wlast_was;
                msix_bresp_o  = 2'b10   ;

                if (msix_bvalid_o && msix_bready_i) begin
                    wlast_was_next = '0;
                end
            end
            default : begin
            end
        endcase
    end
    
endmodule