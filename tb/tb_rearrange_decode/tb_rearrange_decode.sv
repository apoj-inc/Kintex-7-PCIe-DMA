import kdma_pcie_headers_pkg::*;

module tb_rearrange_decode;

parameter BAR_COUNT         = 6;

parameter DMA_CHANNEL_COUNT = 8;
parameter PIPELINE_CAPACITY = 4;

parameter TOTAL_ID_COUNT = DMA_CHANNEL_COUNT * PIPELINE_CAPACITY;

logic [128+5+5+8 - 1:0] pcie_data_queue [$];

logic [7:0] bar_hit_buf;

logic test_done;

logic                      clk                          ;
logic                      rst_n                        ;

logic                      pcie_valid_i                 ;
logic                      pcie_ready_o                 ;
logic [127:0]              pcie_data_i                  ;
logic [4:0]                pcie_sof_i                   ;
logic [4:0]                pcie_eof_i                   ;
logic [7:0]                pcie_bar_hit_i               ;

logic [BAR_COUNT-1:0]      bar_psel_o                   ;
logic                      bar_penable_o                ;
logic [BAR_COUNT-1:0]      bar_pready_i                 ;
logic [63:0]               bar_paddr_o                  ;
logic                      bar_pwrite_o                 ;
logic [127:0]              bar_pwdata_o                 ;
logic [15:0]               bar_pstrb_o                  ;
logic [127:0]              bar_prdata_i      [BAR_COUNT];

logic [TOTAL_ID_COUNT-1:0] dmard_valid_o                ;
logic [TOTAL_ID_COUNT-1:0] dmard_ready_i                ;
logic [127:0]              dmard_data_o                 ;
logic                      dmard_last_o                 ;

logic                      pcie_valid_o                 ;
logic                      pcie_ready_i                 ;
logic [127:0]              pcie_data_o                  ;
logic [15:0]               pcie_tkeep_o                 ;

logic [7:0]                bus_number_i                 ;
logic [4:0]                device_number_i              ;
logic [2:0]                function_number_i            ;

logic                      error_o                      ;

kdma_pcie_tlp_rearrange_decode #(
    .BAR_COUNT         (BAR_COUNT        ),

    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
    .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
) dut (
    .clk               (clk              ),
    .rst_n             (rst_n            ),

    .pcie_valid_i      (pcie_valid_i     ),
    .pcie_ready_o      (pcie_ready_o     ),
    .pcie_data_i       (pcie_data_i      ),
    .pcie_sof_i        (pcie_sof_i       ),
    .pcie_eof_i        (pcie_eof_i       ),
    .pcie_bar_hit_i    (pcie_bar_hit_i   ),

    .bar_psel_o        (bar_psel_o       ),
    .bar_penable_o     (bar_penable_o    ),
    .bar_pready_i      (bar_pready_i     ),
    .bar_paddr_o       (bar_paddr_o      ),
    .bar_pwrite_o      (bar_pwrite_o     ),
    .bar_pwdata_o      (bar_pwdata_o     ),
    .bar_pstrb_o       (bar_pstrb_o      ),
    .bar_prdata_i      (bar_prdata_i     ),

    .dmard_valid_o     (dmard_valid_o    ),
    .dmard_ready_i     (dmard_ready_i    ),
    .dmard_data_o      (dmard_data_o     ),
    .dmard_last_o      (dmard_last_o     ),

    .pcie_valid_o      (pcie_valid_o     ),
    .pcie_ready_i      (pcie_ready_i     ),
    .pcie_data_o       (pcie_data_o      ),
    .pcie_tkeep_o      (pcie_tkeep_o     ),

    .bus_number_i      (bus_number_i     ),
    .device_number_i   (device_number_i  ),
    .function_number_i (function_number_i),

    .error_o           (error_o          )
);

assign {bus_number_i, device_number_i, function_number_i} = 16'hDEAD;

generate
    for (genvar i = 0; i < BAR_COUNT; i++) begin
        initial begin
            bar_prdata_i[i] <= {$urandom(), $urandom(), $urandom(), $urandom()};
        end
    end
endgenerate

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_ready_i <= '0;
        bar_pready_i <= '0;
    end
    else begin
        pcie_ready_i <= $urandom();
        bar_pready_i <= $urandom();
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_valid_i <= '0;
        {pcie_data_i, pcie_sof_i, pcie_eof_i, pcie_bar_hit_i} <= pcie_data_queue.pop_front();
    end
    else begin
        pcie_valid_i <= (pcie_valid_i && ~pcie_ready_o) ? '1 : $urandom();
        if (pcie_valid_i && pcie_ready_o) begin
            {pcie_data_i, pcie_sof_i, pcie_eof_i, pcie_bar_hit_i} <= pcie_data_queue.pop_front();
        end
    end
end

always #4 clk = ~clk;

initial begin
    test_done = 0;

    clk = 1;
    rst_n = 1;

    #2;
    rst_n = 0;

    #2;
    rst_n = 1;
    
    while (pcie_data_queue.size()) begin
        @(posedge clk);
    end

    repeat (100) @(posedge clk);
    
    test_done = 1;
end

header_dw0_t             hdw0, hdw0_in, hdw0_out;
memory_request_3dw_12_t  mr3d, mr3d_in, mr3d_out;
memory_request_4dw_123_t mr4d, mr4d_in, mr4d_out;
cpl_3dw_12_t             cpl3, cpl3_in, cpl3_out;

assign hdw0_out = pcie_data_o[31:0];
assign mr3d_out = pcie_data_o[127:32];
assign mr4d_out = pcie_data_o[95:32];
assign cpl3_out = pcie_data_o[95:32];

assign hdw0_in = pcie_data_i[31:0];
assign mr3d_in = pcie_data_i[127:32];
assign mr4d_in = pcie_data_i[95:32];
assign cpl3_in = pcie_data_i[95:32];

initial begin
    for (int i = 1; i <= 4; i++) begin
        {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
        {hdw0.fmt, hdw0.tp} = WR_32;
        hdw0.length = i;
        
        mr3d.addr = {$urandom(), 2'($urandom_range(0, 4 - i)), 2'b0};
        mr3d.rsvd = '0;
        mr3d.ldw_be = hdw0.length == 1 ? '0 : '1;
        mr3d.fdw_be = '1;
        mr3d.req_id = $urandom();
        mr3d.tag = $urandom();

        $display("Transaction: addr %x, id %x, tag %x", mr3d.addr, mr3d.req_id, mr3d.tag);
        if (hdw0.length == 1) begin
            pcie_data_queue.push_back({32'($urandom()), mr3d, hdw0, 5'b10000, 5'b11111, 8'(1 << ($urandom_range(0, BAR_COUNT-1)))});
        end
        else begin
            bar_hit_buf = 8'(1 << ($urandom_range(0, BAR_COUNT-1)));
            pcie_data_queue.push_back({32'($urandom()), mr3d, hdw0, 5'b10000, 5'b00000, bar_hit_buf});
            pcie_data_queue.push_back({32'($urandom()), 32'($urandom()), 32'($urandom()), 32'($urandom()), 5'b00000, 1'b1, 4'((hdw0.length-1)*4-1), bar_hit_buf});
        end
    end

    for (int i = 1; i <= 4; i++) begin
        {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
        {hdw0.fmt, hdw0.tp} = RD_32;
        hdw0.length = i;
        
        mr3d.addr = {$urandom(), 2'($urandom_range(0, 4 - i)), 2'b0};
        {mr3d.rsvd, mr3d.ldw_be} = '0;
        mr3d.fdw_be = '1;
        mr3d.req_id = $urandom();
        mr3d.tag = $urandom();

        $display("Transaction: addr %x, id %x, tag %x", mr3d.addr, mr3d.req_id, mr3d.tag);
        pcie_data_queue.push_back({32'b0, mr3d, hdw0, 5'b10000, 5'b11011, 8'(1 << ($urandom_range(0, BAR_COUNT-1)))});
    end
    
    for (int i = 1; i <= 4; i++) begin
        {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
        {hdw0.fmt, hdw0.tp} = WR_64;
        hdw0.length = i;

        mr4d.addr_lo = {$urandom(), 2'($urandom_range(0, 4 - i)), 2'b0};
        mr4d.addr_hi = $urandom();
        mr4d.rsvd = '0;
        mr4d.ldw_be = hdw0.length == 1 ? '0 : '1;
        mr4d.fdw_be = '1;
        mr4d.req_id = $urandom();
        mr4d.tag = $urandom();

        $display("Transaction: addr %x, id %x, tag %x", {mr4d.addr_hi, mr4d.addr_lo}, mr4d.req_id, mr4d.tag);
        bar_hit_buf = 8'(1 << ($urandom_range(0, BAR_COUNT-1)));
        pcie_data_queue.push_back({mr4d, hdw0, 5'b10000, 5'b00000, bar_hit_buf});
        pcie_data_queue.push_back({32'($urandom()), 32'($urandom()),32'($urandom()), 32'($urandom()),  5'b00000, 1'b1, 4'((hdw0.length)*4-1), bar_hit_buf});
    end

    for (int i = 1; i <= 4; i++) begin
        {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
        {hdw0.fmt, hdw0.tp} = RD_64;
        hdw0.length = i;
        
        mr4d.addr_lo = {$urandom(), 2'($urandom_range(0, 4 - i)), 2'b0};
        mr4d.addr_hi = $urandom();
        {mr4d.rsvd, mr4d.ldw_be} = '0;
        mr4d.fdw_be = '1;
        mr4d.req_id = $urandom();
        mr4d.tag = $urandom();

        $display("Transaction: addr %x, id %x, tag %x", {mr4d.addr_hi, mr4d.addr_lo}, mr4d.req_id, mr4d.tag);
        pcie_data_queue.push_back({32'b0, mr3d, hdw0, 5'b10000, 5'b11111, 8'(1 << ($urandom_range(0, BAR_COUNT-1)))});
    end
end
    
endmodule