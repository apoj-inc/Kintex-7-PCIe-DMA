import kdma_pcie_headers_pkg::*;

module kdma_dmawr_sink #(
    parameter DMA_CHANNEL_COUNT = 9,
    parameter PIPELINE_CAPACITY    = 4,
    
    parameter AXI_ID_WIDTH = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)
) (
    input  logic                         clk                                  ,
    input  logic                         rst_n                                ,

    input  logic [DMA_CHANNEL_COUNT-1:0] awvalid_i                            ,
    output logic [DMA_CHANNEL_COUNT-1:0] awready_o                            ,
    input  logic [63:0]                  awaddr_i          [DMA_CHANNEL_COUNT],
    input  logic [7:0]                   awlen_i           [DMA_CHANNEL_COUNT],
    input  logic [AXI_ID_WIDTH-1:0]      awid_i            [DMA_CHANNEL_COUNT],
    input  logic [1:0]                   awburst_i         [DMA_CHANNEL_COUNT],
    input  logic [2:0]                   awsize_i          [DMA_CHANNEL_COUNT],

    input  logic [DMA_CHANNEL_COUNT-1:0] wvalid_i                             ,
    output logic [DMA_CHANNEL_COUNT-1:0] wready_o                             ,
    input  logic [127:0]                 wdata_i           [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0] wlast_i                              ,
    input  logic [15:0]                  wstrb_i           [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] bvalid_o                             ,
    input  logic [DMA_CHANNEL_COUNT-1:0] bready_i                             ,
    output logic [AXI_ID_WIDTH-1:0]      bid_o             [DMA_CHANNEL_COUNT],
    output logic [2:0]                   bresp_o           [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] pcie_valid_o                         ,
    input  logic [DMA_CHANNEL_COUNT-1:0] pcie_ready_i                         ,
    output logic [127:0]                 pcie_data_o       [DMA_CHANNEL_COUNT],
    output logic [15:0]                  pcie_tkeep_o      [DMA_CHANNEL_COUNT],
    output logic [DMA_CHANNEL_COUNT-1:0] pcie_tlast_o                         ,
    
    input  logic [7:0]                   bus_number_i                         ,
    input  logic [4:0]                   device_number_i                      ,
    input  logic [2:0]                   function_number_i                    
);

    typedef enum logic [1:0] {
        IDLE    ,
        DMAWR_32,
        DMAWR_64,
        ERR_RESP
    } state_t;

    generate
        genvar i;

        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            state_t state, state_next;

            logic                    bvalid, bvalid_next;
            logic [AXI_ID_WIDTH-1:0] bid   , bid_next   ;
            logic [2:0]              bresp , bresp_next ;

            logic [95:0] buf_for_32, buf_for_32_next;

            logic wlast_was, wlast_was_next;

            header_dw0_t             hdw0;
            memory_request_3dw_12_t  mr3d;
            memory_request_4dw_123_t mr4d;

            assign bvalid_o[i] = bvalid;
            assign bid_o[i]    = bid   ;
            assign bresp_o[i]  = bresp ;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    state <= IDLE;

                    bvalid <= '0;
                    bid    <= '0;
                    bresp  <= '0;

                    buf_for_32 <= '0;

                    wlast_was <= '0;
                end
                else begin
                    state <= state_next;

                    bvalid <= bvalid_next;
                    bid    <= bid_next   ;
                    bresp  <= bresp_next ;

                    buf_for_32 <= buf_for_32_next;

                    wlast_was <= wlast_was_next;
                end
            end

            always_comb begin
                state_next = state;

                case (state)
                    IDLE    : begin
                        if (awvalid_i[i] && awready_o[i]) begin
                            if (awsize_i[i] == 3'b100 && awburst_i[i] == 2'b01) begin
                                if (awaddr_i[i][63:32] == '0) begin
                                    state_next = DMAWR_32;
                                end
                                else begin
                                    state_next = DMAWR_64;
                                end
                            end
                            else begin
                                state_next = ERR_RESP;
                            end
                        end
                        else begin
                            state_next = IDLE;
                        end
                    end
                    DMAWR_32, DMAWR_64, ERR_RESP: begin
                        if (bvalid_o && bready_i) begin
                            state_next = IDLE;
                        end
                        else begin
                            state_next = state;
                        end
                    end
                    default : begin
                        state_next = IDLE;
                    end
                endcase
            end

            always_comb begin
                awready_o[i] = '0;

                wready_o[i]  = '0;
                
                pcie_valid_o[i] = '0;
                pcie_data_o[i]  = '0;
                pcie_tkeep_o[i] = '0;
                pcie_tlast_o[i] = '0;

                hdw0 = '0;
                mr3d = '0;
                mr4d = '0;

                bvalid_next = bvalid;
                bid_next    = bid   ;
                bresp_next  = bresp ;

                buf_for_32_next = buf_for_32;

                wlast_was_next = wlast_was;

                case (state)
                    IDLE    : begin
                        if (awvalid_i[i]) begin
                            bid_next   = awid_i[i];

                            if (awsize_i[i] == 3'b100 && awburst_i[i] == 2'b01) begin
                                bresp_next = 3'b000;

                                {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.qos, hdw0.rsvd_0, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
                                hdw0.length = awlen_i[i] << 2;

                                if (awaddr_i[i][63:32] == '0) begin
                                    {hdw0.fmt, hdw0.tp} = WR_32;
                                    {mr3d.addr, mr3d.rsvd} = awaddr_i[i][31:0];
                                    mr3d.req_id = {bus_number_i, device_number_i, function_number_i};
                                    mr3d.tag    = awid_i[i];
                                    mr3d.ldw_be = '1;
                                    mr3d.fdw_be = '1;

                                    awready_o[i] = '1;

                                    buf_for_32_next = {mr3d, hdw0};
                                end
                                else begin
                                    {hdw0.fmt, hdw0.tp} = WR_64;
                                    {mr4d.addr_hi, mr4d.addr_lo, mr4d.rsvd} = awaddr_i[i];
                                    mr4d.req_id = {bus_number_i, device_number_i, function_number_i};
                                    mr4d.tag    = awid_i[i];
                                    mr4d.ldw_be = '1;
                                    mr4d.fdw_be = '1;

                                    awready_o[i] = pcie_ready_i[i];

                                    pcie_valid_o[i] = '1;
                                    pcie_data_o[i]  = {mr4d, hdw0};
                                    pcie_tkeep_o[i] = '1;
                                    pcie_tlast_o[i] = '0;
                                end
                            end
                            else begin
                                bresp_next = 3'b010; // slverr
                                awready_o[i] = '1;
                            end
                        end
                    end
                    DMAWR_32: begin
                        if (!wlast_was) begin
                            wready_o[i] = pcie_ready_i[i];

                            pcie_valid_o[i] = wvalid_i[i];
                            pcie_data_o[i]  = {wdata_i[i][31:0], buf_for_32};
                            pcie_tkeep_o[i] = '1;
                            pcie_tlast_o[i] = '0;

                            buf_for_32_next = wready_o[i] && wvalid_i[i] ? wdata_i[i][127:32] : buf_for_32_next;

                            wlast_was_next = wvalid_i[i] && wready_o[i] && wlast_i[i] ? '1 : wlast_was;
                        end
                        else begin
                            wready_o[i] = '0;

                            pcie_valid_o[i] = bvalid_o ? '1 : '0;
                            pcie_data_o[i]  = {'0, buf_for_32};
                            pcie_tkeep_o[i] = 16'h0FFF;
                            pcie_tlast_o[i] = '1;

                            wlast_was_next = pcie_valid_o[i] && pcie_ready_i[i] ? '0 : wlast_was;

                            bvalid_next = bvalid_o[i] && bready_i[i] ? '0 :
                                            pcie_valid_o[i] && pcie_ready_i[i] && pcie_tlast_o[i] ? '1 : bvalid;
                        end
                    end
                    DMAWR_64: begin
                        wready_o[i] = bvalid_o ? '0 : pcie_ready_i[i];

                        pcie_valid_o[i] = bvalid_o ? '0 : wvalid_i[i];
                        pcie_data_o[i]  = wdata_i[i];
                        pcie_tkeep_o[i] = '1;
                        pcie_tlast_o[i] = wlast_i[i];

                        bvalid_next = bvalid_o[i] && bready_i[i] ? '0 :
                                        wvalid_i[i] && wready_o[i] && wlast_i[i] ? '1 : bvalid;
                    end
                    ERR_RESP: begin
                        wready_o[i] = '1;

                        pcie_valid_o[i] = '0;
                        pcie_data_o[i]  = '0;
                        pcie_tkeep_o[i] = '0;
                        pcie_tlast_o[i] = '0;

                        bvalid_next = bvalid_o[i] && bready_i[i] ? '0 :
                                        wvalid_i[i] && wready_o[i] && wlast_i[i] ? '1 : bvalid;
                    end
                    default : begin
                    end
                endcase
            end
        end
    endgenerate
    
endmodule