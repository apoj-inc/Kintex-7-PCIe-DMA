module tb_aurora_transfer;

parameter DMA_CHANNEL_COUNT = 8;
parameter DMA_CHANNEL_COUNT_W = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT);

parameter TEST_STOP = 1024;

logic test_done, check_data;

logic aurora_clk ;
logic aurora_rstn;

logic        aurora_valid_wr, aurora_valid_rd;
logic        aurora_ready_wr, aurora_ready_rd;
logic [63:0] aurora_data_wr , aurora_data_rd ;

logic [DMA_CHANNEL_COUNT-1:0] dma_send_valid_rd                    ;
logic [DMA_CHANNEL_COUNT-1:0] dma_send_ready_rd                    ;
logic [127:0]                 dma_send_data_rd  [DMA_CHANNEL_COUNT];

logic                           dma_arbed_valid  ;
logic                           dma_arbed_ready  ;
logic [127:0]                   dma_arbed_data   ;
logic [DMA_CHANNEL_COUNT_W-1:0] dma_arbed_channel;

assign aurora_ready_rd = '1;

logic dma_clk ;
logic dma_rstn;

logic [DMA_CHANNEL_COUNT-1:0] dma_receive_valid_wr;
logic [127:0]                 dma_receive_data_wr ;

logic [31:0] send_counters [DMA_CHANNEL_COUNT];
logic [31:0] rec_counters  [DMA_CHANNEL_COUNT];

always #4  dma_clk    = ~dma_clk   ;
always #10 aurora_clk = ~aurora_clk;

generate
    for (genvar i = 0; i < DMA_CHANNEL_COUNT; i++) begin : afifos
        logic         valid_i ;
        logic         ready_o ;
        logic [127:0] data_i  ;

        cdc_stream_afifo #(
            .DATA_WIDTH (128),
            .ADDR_WIDTH (4  )
        ) u_cdc_stream_afifo (
            .clk_wr   (dma_clk ),
            .rst_n_wr (dma_rstn),

            .data_i   (data_i  ),
            .valid_i  (valid_i ),
            .ready_o  (ready_o ),
            .free_o   (        ),

            .clk_rd   (aurora_clk ),
            .rst_n_rd (aurora_rstn),

            .data_o  (dma_send_data_rd  [i]),
            .valid_o (dma_send_valid_rd [i]),
            .ready_i (dma_send_ready_rd [i]),
            .count_o (                     )
        );

        always_ff @(posedge dma_clk or negedge dma_rstn) begin
            if (!dma_rstn) begin
                valid_i <= '0;

                for (int i = 0; i < 4; i++) begin
                    data_i[32 * i +: 32] <= $urandom();
                end

                send_counters[i] <= '0;
            end
            else begin
                if (send_counters[i] < TEST_STOP) begin
                    valid_i <= $urandom_range(0, 3) == 3 ? '1 : 0;
                end
                else begin
                    valid_i <= '0;
                end

                if (valid_i && ready_o) begin
                    for (int i = 0; i < 4; i++) begin
                        data_i[32 * i +: 32] <= $urandom();
                    end
                    send_counters[i] <= send_counters[i] + 1;
                end
            end
        end

        always_ff @(posedge aurora_clk or negedge aurora_rstn) begin
            if (!aurora_rstn) begin
                rec_counters[i] <= '0;
            end
            else begin
                if (dma_receive_valid_wr[i]) begin
                    rec_counters[i] <= rec_counters[i] + 1;
                end
            end
        end

        logic [127:0] check_in  [$];
        logic [127:0] check_out [$];

        always @(posedge dma_clk) begin
            if (valid_i && ready_o) begin
                check_in.push_back(data_i);
            end
        end

        always @(posedge aurora_clk) begin
            if (dma_receive_valid_wr[i]) begin
                check_out.push_back(dma_receive_data_wr);
            end
        end

        initial begin
            logic [127:0] exp, rec;
            @(posedge check_data);

            exp = check_in.size();
            rec = check_out.size();

            assert (exp == rec) 
            else begin
                $error("Error size in %d out %d ch %d", exp, rec, i);
                $finish();
            end

            while (check_in.size()) begin
                exp = check_in.pop_front();
                rec = check_out.pop_front();

                assert (exp == rec) 
                else begin
                    $error("Error data in %x out %x ch %d", exp, rec, i);
                    $finish();
                end
            end
        end
    end
endgenerate

stream_arbiter #(
    .DATA_WIDTH (128              ),
    .INPUT_NUM  (DMA_CHANNEL_COUNT)
) u_stream_arbiter (
    .ACLK    (aurora_clk ),
    .ARESETn (aurora_rstn),

    .data_i  (dma_send_data_rd ),
    .valid_i (dma_send_valid_rd),
    .ready_o (dma_send_ready_rd),

    .data_o  (dma_arbed_data   ),
    .valid_o (dma_arbed_valid  ),
    .ready_i (dma_arbed_ready  ),
    .sel_o   (dma_arbed_channel)
);

kdma_aurora_sender #(
    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
) u_kdma_aurora_sender (
    .clk            (aurora_clk       ),
    .rst_n          (aurora_rstn      ),

    .dma_valid_i    (dma_arbed_valid  ),
    .dma_ready_o    (dma_arbed_ready  ),
    .dma_data_i     (dma_arbed_data   ),
    .dma_channel_i  (dma_arbed_channel),

    .aurora_valid_o (aurora_valid_wr  ),
    .aurora_ready_i (aurora_ready_wr  ),
    .aurora_data_o  (aurora_data_wr   )
);

stream_fifo #(
    .DATA_WIDTH (64),
    .FIFO_DEPTH (4 )
) u_stream_fifo (
    .ACLK    (aurora_clk     ),
    .ARESETn (aurora_rstn    ),
    
    .data_i  (aurora_data_wr ),
    .valid_i (aurora_valid_wr),
    .ready_o (aurora_ready_wr),
    .free_o  (               ),

    .data_o  (aurora_data_rd ),
    .valid_o (aurora_valid_rd),
    .ready_i (aurora_ready_rd),
    .count_o (               )
);


kdma_aurora_receiver #(
    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
) u_kdma_aurora_receiver (
    .clk            (aurora_clk          ),
    .rst_n          (aurora_rstn         ),

    .aurora_valid_i (aurora_valid_rd     ),
    .aurora_data_i  (aurora_data_rd      ),

    .dma_valid_o    (dma_receive_valid_wr),
    .dma_data_o     (dma_receive_data_wr )
);

initial begin
    aurora_clk = '1;
    dma_clk    = '1;
    test_done  = '0;
    check_data = '0;

    #1;

    aurora_rstn = '0;
    dma_rstn    = '0;

    fork
        begin   
            @(posedge aurora_clk);
            aurora_rstn = '1;
        end
        begin
            @(posedge dma_clk);
            dma_rstn = '1;
        end
    join

    @(posedge aurora_clk);

    while (check_data == '0) begin
        logic thing;
        thing = '1;
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            if (rec_counters[i] != TEST_STOP) begin
                thing = '0;
            end
        end

        if (thing == 1) begin
            repeat (50) @(posedge aurora_clk);
        end

        check_data = thing;
        @(posedge aurora_clk);
    end

    @(posedge aurora_clk);
    test_done = '1;

end


endmodule