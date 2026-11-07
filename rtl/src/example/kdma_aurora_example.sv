module kdma_aurora_example (
    input  logic clk_100m ,

    input  logic gtx_clk_p,
    input  logic gtx_clk_n,

    input  logic gtx_rx_p ,
    input  logic gtx_rx_n ,

    output logic gtx_tx_p ,
    output logic gtx_tx_n 
);

    logic        pma_init;
    logic        reset_pb;

    logic        user_clk;
    logic        sys_rst ;

    logic        tx_valid;
    logic        tx_ready;
    logic [63:0] tx_data ;

    logic        rx_valid;
    logic [63:0] rx_data ;


    logic [31:0] counter = '0;

    assign pma_init = counter < 100;
    assign reset_pb = counter < 150;

    always_ff @(posedge clk_100m) begin : blockName
        counter <= (counter == 150) ? counter : counter + 1;
    end

    kdma_ila_0 u_ila_0 (
        .clk    (clk_100m),

        .probe0 (pma_init),
        .probe1 (reset_pb),
        .probe2 ('0      ),
        .probe3 ('0      ),
        .probe4 ('0      ),
        .probe5 ('0      ),
        .probe6 ('0      ),
        .probe7 ('0      ),
        .probe8 ('0      ),
        .probe9 (counter )
    );

    kdma_ila_0 u_ila_1 (
        .clk    (user_clk),

        .probe0 ('0      ),
        .probe1 ('0      ),
        .probe2 ('0      ),
        .probe3 (sys_rst ),
        .probe4 (tx_valid),
        .probe5 (tx_ready),
        .probe6 (tx_data ),
        .probe7 (rx_valid),
        .probe8 (rx_data ),
        .probe9 ('0      )
    );

    kdma_aurora_traffic_gen u_kdma_aurora_traffic_gen (
        .clk_i   (user_clk),
        .rstn_i  (~sys_rst),

        .valid_o (tx_valid),
        .ready_i (tx_ready),
        .data_o  (tx_data )
    );

    kdma_aurora_64b66b_0 dut (
        .pma_init          (pma_init ),
        .reset_pb          (reset_pb ),

        .drp_clk_in        (clk_100m ),
        .init_clk          (clk_100m ),

        .gt_refclk1_p      (gtx_clk_p),
        .gt_refclk1_n      (gtx_clk_n),

        .rxp               (gtx_rx_p ),
        .rxn               (gtx_rx_n ),
        .txp               (gtx_tx_p ),
        .txn               (gtx_tx_n ),

        .user_clk_out      (user_clk ),
        .sys_reset_out     (sys_rst  ),

        .s_axi_tx_tvalid   (tx_valid ),
        .s_axi_tx_tready   (tx_ready ),
        .s_axi_tx_tdata    (tx_data  ),

        .m_axi_rx_tvalid   (rx_valid ),
        .m_axi_rx_tdata    (rx_data  ),

        .s_axi_awaddr      ('0       ),
        .s_axi_araddr      ('0       ),
        .s_axi_wdata       ('0       ),
        .s_axi_wstrb       ('0       ),
        .s_axi_awvalid     ('0       ),
        .s_axi_rready      ('1       ),
        .s_axi_bready      ('1       ),
        .s_axi_arvalid     ('0       ),
        .s_axi_wvalid      ('0       ),

        .gt_rxcdrovrden_in ('0       ),
        .power_down        ('0       ),
        .loopback          ('0       )
    );
    
endmodule