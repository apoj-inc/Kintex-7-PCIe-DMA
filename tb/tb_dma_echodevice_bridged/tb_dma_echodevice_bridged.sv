module tb_dma_echodevice_bridged;

parameter BAR_COUNT                                 = 4         ;

parameter DMA_CHANNEL_COUNT                         = 2         ;
parameter PIPELINE_CAPACITY                         = 4         ;

parameter     DMA_BYTES_WIDTH                       = 22        ;
parameter     DMA_OFFFSET_WIDTH                     = 22        ;

parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{2{16  }};
parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{16  }};
parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{16  }};
parameter     DMA_TQ_DEPTH                          = 2         ;

parameter     MAX_WQ_DEPTH                          = 16        ;
parameter     MAX_RQ_DEPTH                          = 16        ;

parameter AXI_ID_WIDTH   = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY);
parameter MSIX_COUNT     = DMA_CHANNEL_COUNT                                     ;

logic                  clk              ;
logic                  rst_n            ;

logic                  pcie_valid_i     ;
logic                  pcie_ready_o     ;
logic [127:0]          pcie_data_i      ;
logic [4:0]            pcie_sof_i       ;
logic [4:0]            pcie_eof_i       ;
logic [7:0]            pcie_bar_hit_i   ;

logic                  pcie_valid_o     ;
logic                  pcie_ready_i     ;
logic [127:0]          pcie_data_o      ;
logic [15:0]           pcie_tkeep_o     ;
logic                  pcie_tlast_o     ;

logic [7:0]            bus_number_i     ;
logic [4:0]            device_number_i  ;
logic [2:0]            function_number_i;

logic [MSIX_COUNT-1:0] user_irq_i       ;

assign {bus_number_i, device_number_i, function_number_i} = 'hDEAD;

kdma_echodevice_bridged #(
    .BAR_COUNT         (BAR_COUNT        ),

    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
    .PIPELINE_CAPACITY (PIPELINE_CAPACITY),

    .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH  ),
    .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH),

    .DMA_WORD_BYTES    (DMA_WORD_BYTES   ),
    .DMA_WQ_DEPTH      (DMA_WQ_DEPTH     ),
    .DMA_RQ_DEPTH      (DMA_RQ_DEPTH     ),
    .DMA_TQ_DEPTH      (DMA_TQ_DEPTH     ),

    .MAX_WQ_DEPTH      (MAX_WQ_DEPTH     ),
    .MAX_RQ_DEPTH      (MAX_RQ_DEPTH     )
) dut (
    .clk               (clk              ),
    .rst_n             (rst_n            ),

    .pcie_valid_i      (pcie_valid_i     ),
    .pcie_ready_o      (pcie_ready_o     ),
    .pcie_data_i       (pcie_data_i      ),
    .pcie_sof_i        (pcie_sof_i       ),
    .pcie_eof_i        (pcie_eof_i       ),
    .pcie_bar_hit_i    (pcie_bar_hit_i   ),

    .pcie_valid_o      (pcie_valid_o     ),
    .pcie_ready_i      (pcie_ready_i     ),
    .pcie_data_o       (pcie_data_o      ),
    .pcie_tkeep_o      (pcie_tkeep_o     ),
    .pcie_tlast_o      (pcie_tlast_o     ),

    .bus_number_i      (bus_number_i     ),
    .device_number_i   (device_number_i  ),
    .function_number_i (function_number_i),

    .user_irq_i        (user_irq_i       )
);

always #4 clk = ~clk;

semaphore pcie_data_lock;
logic test_done;
logic tlast_was;

header_dw0_t             hdw0, hdw0_event, hdw0_in, hdw0_out;
memory_request_3dw_12_t  mr3d, mr3d_event, mr3d_in, mr3d_out;
memory_request_4dw_123_t mr4d, mr4d_event, mr4d_in, mr4d_out;
cpl_3dw_12_t             cpl3, cpl3_event, cpl3_in, cpl3_out;

logic [32:0] pcie_in_data_logger  [$];
logic [32:0] pcie_out_data_logger [$];

always @(posedge clk) begin
    if (pcie_valid_i && pcie_ready_o) begin
        pcie_in_data_logger.push_back({pcie_sof_i[4], pcie_data_i[0  +: 32]});
        if (!pcie_eof_i[4] || (pcie_eof_i >= 5'b10111)) begin
            pcie_in_data_logger.push_back({1'b0, pcie_data_i[32 +: 32]});
        end
        if (!pcie_eof_i[4] || (pcie_eof_i >= 5'b11011)) begin
            pcie_in_data_logger.push_back({1'b0, pcie_data_i[64 +: 32]});
        end
        if (!pcie_eof_i[4] || (pcie_eof_i >= 5'b11111)) begin
            pcie_in_data_logger.push_back({1'b0, pcie_data_i[96 +: 32]});
        end
    end

    if (pcie_valid_o && pcie_ready_i) begin
        pcie_out_data_logger.push_back({tlast_was, pcie_data_o[0  +: 32]});
        if (pcie_tkeep_o[7:4] == 4'hF) begin
            pcie_out_data_logger.push_back({1'b0, pcie_data_o[32 +: 32]});
        end
        if (pcie_tkeep_o[11:8] == 4'hF) begin
            pcie_out_data_logger.push_back({1'b0, pcie_data_o[64 +: 32]});
        end
        if (pcie_tkeep_o[15:12] == 4'hF) begin
            pcie_out_data_logger.push_back({1'b0, pcie_data_o[96 +: 32]});
        end
    end
end

logic [128+5+5+8 - 1:0] pcie_data_queue [$];

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_ready_i <= '0;
    end
    else begin
        pcie_ready_i <= $urandom();
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_valid_i <= '0;
    end
    else begin
        pcie_valid_i <= pcie_data_queue.size() ?
                        (pcie_valid_i && ~pcie_ready_o) ? '1 : $urandom()
                        : '0;
        if (pcie_valid_i && pcie_ready_o) begin
            pcie_data_queue.pop_front();
        end
    end
end

always_comb begin
    {pcie_data_i, pcie_sof_i, pcie_eof_i, pcie_bar_hit_i} = pcie_data_queue[0];
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tlast_was <= '1;
    end
    else begin
        if (pcie_valid_o && pcie_ready_i) begin
            tlast_was <= pcie_tlast_o;
        end
    end
end


always @(posedge clk) begin
    if (pcie_valid_o && pcie_ready_i) begin
        if (tlast_was) begin
            case ({hdw0_out.fmt, hdw0_out.tp})
                RD_32, RD_64: begin
                    pcie_data_lock.get(1);
                    $display("Processing read request...", $time);
                    {hdw0_event.rsvd_2, hdw0_event.rsvd_1, hdw0_event.rsvd_0, hdw0_event.qos, hdw0_event.digest, hdw0_event.err, hdw0_event.attr, hdw0_event.addr_tran} = '0;
                    {hdw0_event.fmt, hdw0_event.tp} = CPLD;
                    if (hdw0_out.length == 4) begin
                        hdw0_event.length = hdw0_out.length;
                    end
                    else if ((hdw0_out.length / 2) % 4 != 0) begin
                        hdw0_event.length = hdw0_out.length / 2 + 2;
                    end
                    else begin
                        hdw0_event.length = hdw0_out.length / 2;
                    end

                    cpl3_event.req_id   = mr3d_out.req_id;
                    cpl3_event.tag      = mr3d_out.tag;
                    cpl3_event.rsvd     = '0;
                    cpl3_event.addr_lo  = '0;
                    cpl3_event.cpl_id   = $urandom();
                    cpl3_event.cpl_sts  = '0;
                    cpl3_event.bcm      = '0;
                    cpl3_event.byte_cnt = hdw0_out.length << 2;

                    pcie_data_queue.push_back({$urandom(), cpl3_event, hdw0_event, 5'b10000, 5'b00000, 8'h0});
                    for (int i = 0; i <= (hdw0_event.length - 1) / 4; i++) begin
                        pcie_data_queue.push_back({$urandom(), $urandom(), $urandom(), $urandom(), 5'b00000, 1'(i == (hdw0_event.length - 1) / 4), 4'b1011, 8'h0});
                    end
                    if (hdw0_out.length != 4) begin
                        if ((hdw0_out.length / 2) % 4 != 0) begin
                            hdw0_event.length = hdw0_out.length / 2 - 2;
                        end
                        else begin
                            hdw0_event.length = hdw0_out.length / 2;
                        end

                        cpl3_event.req_id   = mr3d_out.req_id;
                        cpl3_event.tag      = mr3d_out.tag;
                        cpl3_event.rsvd     = '0;
                        cpl3_event.addr_lo  = '0;
                        cpl3_event.cpl_id   = $urandom();
                        cpl3_event.cpl_sts  = '0;
                        cpl3_event.bcm      = '0;
                        cpl3_event.byte_cnt = hdw0_event.length << 2;

                        pcie_data_queue.push_back({$urandom(), cpl3_event, hdw0_event, 5'b10000, 5'b00000, 8'h0});
                        for (int i = 0; i <= (hdw0_event.length - 1) / 4; i++) begin
                            pcie_data_queue.push_back({$urandom(), $urandom(), $urandom(), $urandom(), 5'b00000, 1'(i == (hdw0_event.length - 1) / 4), 4'b1011, 8'h0});
                        end
                    end

                    pcie_data_lock.put(1);
                end 
                default: begin
                end
            endcase
        end
    end
end

assign hdw0_out = pcie_data_o[31:0];
assign mr3d_out = pcie_data_o[95:32];
assign mr4d_out = pcie_data_o[127:32];
assign cpl3_out = pcie_data_o[95:32];

assign hdw0_in = pcie_data_i[31:0];
assign mr3d_in = pcie_data_i[95:32];
assign mr4d_in = pcie_data_i[127:32];
assign cpl3_in = pcie_data_i[95:32];

assign mr3d.req_id = 'hBEEF;
assign mr4d.req_id = 'hBEEF;

logic check_queues;

initial begin
    check_queues = '0;
    test_done = '0;
    clk = 0;
    #2;
    rst_n = 0;
    user_irq_i = '0;

    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    repeat (1000) @(posedge clk);

    check_queues = '1;

    #10;
    
    test_done = '1;
end

initial begin
    logic [31:0] dmard_data [DMA_CHANNEL_COUNT][$];
    logic [31:0] dmawr_data [DMA_CHANNEL_COUNT][$];

    logic [32:0] word_buffer;
    logic [31:0] channel;
    
    header_dw0_t             hdw0_checker;
    memory_request_3dw_12_t  mr3d_checker;
    memory_request_4dw_123_t mr4d_checker;
    cpl_3dw_12_t             cpl3_checker;

    @(posedge check_queues);

    while (pcie_in_data_logger.size) begin
        word_buffer = pcie_in_data_logger.pop_front();
        hdw0_checker = word_buffer[31:0];

        if ({hdw0_checker.fmt, hdw0_checker.tp} == CPLD) begin
            word_buffer = pcie_in_data_logger.pop_front();
            cpl3_checker[31:0] = word_buffer[31:0];

            word_buffer = pcie_in_data_logger.pop_front();
            cpl3_checker[63:32] = word_buffer[31:0];

            channel = cpl3_checker.tag[7:AXI_ID_WIDTH];

            while (pcie_in_data_logger.size && (pcie_in_data_logger[0][32] == '0)) begin
                word_buffer = pcie_in_data_logger.pop_front();
                dmard_data[channel].push_back(word_buffer[31:0]);
            end
        end
        else begin
            while (pcie_in_data_logger.size && pcie_in_data_logger[0][32] == '0) begin
                word_buffer = pcie_in_data_logger.pop_front();
            end
        end
    end

    while (pcie_out_data_logger.size) begin
        word_buffer = pcie_out_data_logger.pop_front();
        hdw0_checker = word_buffer[31:0];

        if (({hdw0_checker.fmt, hdw0_checker.tp} == WR_32 || {hdw0_checker.fmt, hdw0_checker.tp} == WR_64) && hdw0_checker.length != 1) begin
            word_buffer = pcie_out_data_logger.pop_front();
            mr3d_checker[31:0] = word_buffer[31:0];

            word_buffer = pcie_out_data_logger.pop_front();
            mr3d_checker[63:32] = word_buffer[31:0];

            if ({hdw0_checker.fmt, hdw0_checker.tp} == WR_64) begin
                word_buffer = pcie_out_data_logger.pop_front();
                mr4d_checker = {word_buffer, mr3d_checker};
                
                channel = mr4d_checker.addr_lo[29:(12 - 2)];
                $display("%h", mr4d_checker);
            end
            else begin
                channel = mr3d_checker.addr[29:(12 - 2)];
                $display("%h", mr3d_checker);
            end

            while (pcie_out_data_logger.size && (pcie_out_data_logger[0][32] == '0)) begin
                word_buffer = pcie_out_data_logger.pop_front();
                dmawr_data[channel].push_back(word_buffer[31:0]);
            end
        end
        else begin
            while (pcie_out_data_logger.size && pcie_out_data_logger[0][32] == '0) begin
                word_buffer = pcie_out_data_logger.pop_front();
            end
        end
    end

    for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
        $display("Checking channel %d...", i);
        while (dmard_data[i].size) begin
            assert (dmard_data[i].pop_front() == dmawr_data[i].pop_front())
            else $display("Error");
        end
        $display("Success!");
    end
end

task automatic pcie_reg_write(
    input  logic [63:0]          address ,
    input  logic [63:0]          data    ,
    input  logic                 write_64,
    input  logic [BAR_COUNT-1:0] bar_hit 
);
    logic [63:0] data_endian_fix;
    data_endian_fix[0 +: 32] = {data[0 +: 8], data[8 +: 8], data[16 +: 8], data[24 +: 8]};
    data_endian_fix[(0 + 32) +: 32] = {data[(0 + 32) +: 8], data[(8 + 32) +: 8], data[(16 + 32) +: 8], data[(24 + 32) +: 8]};

    {hdw0.rsvd_2, hdw0.rsvd_1, hdw0.rsvd_0, hdw0.qos, hdw0.digest, hdw0.err, hdw0.attr, hdw0.addr_tran} = '0;
    
    if (address[63:32] == '0) begin
        {hdw0.fmt, hdw0.tp} = WR_32;
        {mr3d.addr, mr3d.rsvd} = address[31:0];
        mr3d.tag = $urandom();

        if (!write_64) begin
            hdw0.length = 1;
            mr3d.fdw_be = '1;
            mr3d.ldw_be = '0;
            pcie_data_queue.push_back({data_endian_fix[31:0], mr3d, hdw0, 5'b10000, 5'b11111, 8'(bar_hit)});
        end
        else begin
            hdw0.length = 2;
            mr3d.fdw_be = '1;
            mr3d.ldw_be = '1;
            pcie_data_queue.push_back({data_endian_fix[31:0], mr3d, hdw0, 5'b10000, 5'b00000, 8'(bar_hit)});
            pcie_data_queue.push_back({96'h0, data_endian_fix[63:32], 5'b00000, 5'b10011, 8'(bar_hit)});
        end
    end
    else begin
        {hdw0.fmt, hdw0.tp} = WR_32;
        {mr4d.addr_hi, mr4d.addr_lo, mr4d.rsvd} = address;
        mr4d.tag = $urandom();

        hdw0.length = 1 + write_64;
        mr4d.fdw_be = '1;
        mr4d.ldw_be = write_64 ? '1 : '0;
        pcie_data_queue.push_back({mr4d, hdw0, 5'b10000, 5'b00000, 8'(bar_hit)});
        pcie_data_queue.push_back({64'h0, data_endian_fix, 5'b00000, 5'('b10011 + write_64*4), 8'(bar_hit)});
    end
endtask

initial begin
    pcie_data_lock = new(1);

    pcie_data_lock.get(1);

    pcie_reg_write(
        .address  (64'h9170000C),
        .data     (64'h1),
        .write_64 ('0),
        .bar_hit  (4'b1100)
    );

    pcie_reg_write(
        .address  (64'h99170000C),
        .data     (64'h1),
        .write_64 ('0),
        .bar_hit  (4'b1100)
    );

    for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) begin
        pcie_reg_write(
            .address  (64'('h91700000 + i * 'h10)),
            .data     (64'(('hF000_0000_0000_0000 >> (32 * (i%2))) + i * 'h4)),
            .write_64 ('1),
            .bar_hit  (4'b0011)
        );
        pcie_reg_write(
            .address  (64'('h91700008 + i * 'h10)),
            .data     (64'(('h0 << 32) | $urandom())),
            .write_64 ('1),
            .bar_hit  (4'b0011)
        );

        pcie_reg_write(
            .address  (64'('h91700044 + i * 'h40)),
            .data     (64'('hFFFF_FFFF_0000_0000 + i * 'h1000)),
            .write_64 ('1),
            .bar_hit  (4'b1100)
        );
    end

    pcie_reg_write(
        .address  (64'h91701008),
        .data     (64'(('h400 << 32) | 0)),
        .write_64 ('1),
        .bar_hit  (4'b1100)
    );

    pcie_reg_write(
        .address  (64'h91701000),
        .data     (64'(('h400 << 32) | 32'h400)),
        .write_64 ('1),
        .bar_hit  (4'b1100)
    );

    pcie_reg_write(
        .address  (64'h91701018),
        .data     (64'(('h400 << 32) | 0)),
        .write_64 ('1),
        .bar_hit  (4'b1100)
    );

    pcie_reg_write(
        .address  (64'h91701010),
        .data     (64'(('h400 << 32) | 32'h400)),
        .write_64 ('1),
        .bar_hit  (4'b1100)
    );
    
    pcie_data_lock.put(1);
end

endmodule