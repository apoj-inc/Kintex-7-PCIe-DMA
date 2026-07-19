module tb_destraddle;

logic [7:0] pcie_queue [$];
logic [7:0] pcie_destr_queue [$];
logic [7:0] pcie_queue_checked [$];
logic [7:0] pcie_destr_queue_checked [$];
int byte_index;
logic [7:0] expected, received;

logic         clk                 ;
logic         rst_n               ;
logic         pcie_valid_i        ;
logic         pcie_ready_o        ;
logic [127:0] pcie_data_i         ;
logic [4:0]   pcie_sof_i          ;
logic [4:0]   pcie_eof_i          ;
logic [7:0]   pcie_bar_hit_i      ;
logic         pcie_destr_valid_o  ;
logic         pcie_destr_ready_i  ;
logic [127:0] pcie_destr_data_o   ;
logic [7:0]   pcie_destr_bar_hit_o;
logic [4:0]   pcie_destr_eof_o    ;

logic pcie_valid_gate, pcie_valid_val;

logic test_done;

assign pcie_valid_i = pcie_valid_gate & pcie_valid_val;


always @(posedge clk) begin
    if (pcie_valid_i && pcie_ready_o) begin
        if (pcie_sof_i[4] && !pcie_eof_i[4]) begin
            for (int i = pcie_sof_i[3:0]; i < 16; i++) begin
                pcie_queue.push_back(pcie_data_i[i*8 +: 8]);
            end
        end
        else if (!pcie_sof_i[4] && pcie_eof_i[4]) begin
            for (int i = 0; i <= pcie_eof_i[3:0]; i++) begin
                pcie_queue.push_back(pcie_data_i[i*8 +: 8]);
            end
        end
        else if (!pcie_sof_i[4] && !pcie_eof_i[4]) begin
            for (int i = 0; i < 16; i++) begin
                pcie_queue.push_back(pcie_data_i[i*8 +: 8]);
            end
        end
        else begin
            if (pcie_sof_i[3:0] > pcie_eof_i[3:0]) begin
                for (int i = 0; i <= pcie_eof_i[3:0]; i++) begin
                    pcie_queue.push_back(pcie_data_i[i*8 +: 8]);
                end
                for (int i = pcie_sof_i[3:0]; i < 16; i++) begin
                    pcie_queue.push_back(pcie_data_i[i*8 +: 8]);
                end
            end
            else begin
                for (int i = pcie_sof_i[3:0]; i <= pcie_eof_i[3:0]; i++) begin
                    pcie_queue.push_back(pcie_data_i[i*8 +: 8]);
                end
            end
        end
    end
end

always @(posedge clk) begin
    if (pcie_destr_valid_o && pcie_destr_ready_i) begin
        if (!pcie_destr_eof_o[4]) begin
            for (int i = 0; i < 16; i++) begin
                pcie_destr_queue.push_back(pcie_destr_data_o[i*8 +: 8]);
            end
        end
        else begin
            for (int i = 0; i <= pcie_destr_eof_o[3:0]; i++) begin
                pcie_destr_queue.push_back(pcie_destr_data_o[i*8 +: 8]);
            end
        end
    end
end

always #4 clk = ~clk;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_destr_ready_i <= '0;
    end
    else begin
        pcie_destr_ready_i <= $urandom();
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_valid_gate <= '0;
    end
    else begin
        if (pcie_valid_i && pcie_ready_o || !pcie_valid_i) begin
            pcie_valid_gate <= $urandom();
        end
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i = 0; i < 4; i++) begin
            pcie_data_i[i*32 +: 32] <= {8{4'($urandom_range(0, 15))}};
        end
    end
    else begin
        if (pcie_valid_i && pcie_ready_o) begin
            for (int i = 0; i < 4; i++) begin
                pcie_data_i[i*32 +: 32] <= {8{4'($urandom_range(0, 15))}};
            end
        end
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcie_bar_hit_i <= $urandom();
    end
    else begin
        if (pcie_valid_i && pcie_ready_o) begin
            if (pcie_eof_i[4]) begin
                pcie_bar_hit_i <= $urandom();
            end
        end
    end
end

kdma_pcie_destraddle dut (
    .clk                  (clk                 ),
    .rst_n                (rst_n               ),

    .pcie_valid_i         (pcie_valid_i        ),
    .pcie_ready_o         (pcie_ready_o        ),
    .pcie_data_i          (pcie_data_i         ),
    .pcie_sof_i           (pcie_sof_i          ),
    .pcie_eof_i           (pcie_eof_i          ),
    .pcie_bar_hit_i       (pcie_bar_hit_i      ),

    .pcie_destr_valid_o   (pcie_destr_valid_o  ),
    .pcie_destr_ready_i   (pcie_destr_ready_i  ),
    .pcie_destr_data_o    (pcie_destr_data_o   ),
    .pcie_destr_bar_hit_o (pcie_destr_bar_hit_o),
    .pcie_destr_eof_o     (pcie_destr_eof_o    )
);

initial begin
    test_done = 0;
    byte_index = '0;

    clk = '0;
    rst_n = '1;

    for (int iter = 0; iter < 100; iter++) begin
        #2;
        rst_n = '0;

        pcie_valid_val = '0;
        #5;
        rst_n = '1;

        @(posedge clk); // single cycle
        pcie_valid_val = '1;
        pcie_sof_i = 5'b10000;
        pcie_eof_i = 5'b11111;

        // non-straddled aligned
        @(posedge clk);
        while (!(pcie_valid_i && pcie_ready_o)) begin
            @(posedge clk);
        end
        pcie_valid_val = '1;
        pcie_sof_i = 5'b10000;
        pcie_eof_i = 5'b00000;

        for (int i = 0; i < 5; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = 5'b00000;
            pcie_eof_i = {1'(i == 4), 4'($urandom_range(1, 4) * 4 - 1)};
        end

        // non-straddled unaligned
        @(posedge clk);
        while (!(pcie_valid_i && pcie_ready_o)) begin
            @(posedge clk);
        end
        pcie_valid_val = '1;
        pcie_sof_i = 5'b11000;
        pcie_eof_i = 5'b00000;

        for (int i = 0; i < 5; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = 5'b00000;
            pcie_eof_i = {1'(i == 4), 4'($urandom_range(1, 4) * 4 - 1)};
        end

        // non-straddled aligned into double straddled
        @(posedge clk);
        while (!(pcie_valid_i && pcie_ready_o)) begin
            @(posedge clk);
        end
        pcie_valid_val = '1;
        pcie_sof_i = 5'b10000;
        pcie_eof_i = 5'b00000;

        for (int i = 0; i < 5; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = i == 4 ? 5'b11000 : 5'b00000;
            pcie_eof_i = {1'(i == 4), 4'($urandom_range(1, 2) * 4 - 1)};
        end

        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = i == 2 ? 5'b11000 : 5'b00000;
            pcie_eof_i = {1'(i == 2), 4'($urandom_range(1, 2) * 4 - 1)};
        end

        for (int i = 0; i < 6; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = 5'b00000;
            pcie_eof_i = {1'(i == 5), 4'b1111};
        end
        
        // non-straddled unaligned into double straddled
        @(posedge clk);
        while (!(pcie_valid_i && pcie_ready_o)) begin
            @(posedge clk);
        end
        pcie_valid_val = '1;
        pcie_sof_i = 5'b11000;
        pcie_eof_i = 5'b00000;

        for (int i = 0; i < 5; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = i == 4 ? 5'b11000 : 5'b00000;
            pcie_eof_i = {1'(i == 4), 4'($urandom_range(1, 2) * 4 - 1)};
        end

        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = i == 2 ? 5'b11000 : 5'b00000;
            pcie_eof_i = {1'(i == 2), 4'($urandom_range(1, 2) * 4 - 1)};
        end

        for (int i = 0; i < 6; i++) begin
            @(posedge clk);
            while (!(pcie_valid_i && pcie_ready_o)) begin
                @(posedge clk);
            end
            pcie_valid_val = '1;
            pcie_sof_i = 5'b00000;
            pcie_eof_i = {1'(i == 5), 4'b1011};
        end

        @(posedge clk);
        while (!(pcie_valid_i && pcie_ready_o)) begin
            @(posedge clk);
        end

        pcie_valid_val = '0;

        #10;
    end

    assert (pcie_queue.size() == pcie_destr_queue.size()) 
    else   begin
        $error("Data count mismatch: %d bytes incoming, %d bytes outgoing", pcie_queue.size(), pcie_destr_queue.size());
        $display("Incoming, Outgoing:");
        while (pcie_queue.size() && pcie_destr_queue.size()) begin
            $display("%h, %h", pcie_queue.pop_front(), pcie_destr_queue.pop_front());
        end
        $finish();
    end
    $display("Data count check pass!");

    while (pcie_queue.size()) begin
        expected = pcie_queue.pop_front();
        received = pcie_destr_queue.pop_front();

        assert (expected == received)
        else   begin
            $error("Data mismatch: byte %d, expected %h, received %h", byte_index, expected, received);
            
            $display("Incoming, Outgoing:");
            while (pcie_queue_checked.size() && pcie_destr_queue_checked.size()) begin
                $display("%h, %h", pcie_queue_checked.pop_front(), pcie_destr_queue_checked.pop_front());
            end
            $display("Error: %h, %h", expected, received);
            while (pcie_queue.size() && pcie_destr_queue.size()) begin
                $display("%h, %h", pcie_queue.pop_front(), pcie_destr_queue.pop_front());
            end
            $finish();
        end
        pcie_queue_checked.push_back(expected);
        pcie_destr_queue_checked.push_back(received);

        byte_index++;
    end
    $display("Data value check pass!");

    test_done = '1;
end

    
endmodule