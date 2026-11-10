module kdma_aurora_connector #(
    parameter DMA_CHANNEL_COUNT = 8,

    parameter DMA_CHANNEL_COUNT_W = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT)
) (
    input  logic clk_100m  ,

    input  logic gtx_clk_p ,
    input  logic gtx_clk_n ,

    input  logic gtx_rx_p  ,
    input  logic gtx_rx_n  ,

    output logic gtx_tx_p  ,
    output logic gtx_tx_n  ,

    output logic user_clk_o,
    input  logic dma_rstn_i,

    input  logic [DMA_CHANNEL_COUNT-1:0] dma_data_valid_i                    ,
    output logic [DMA_CHANNEL_COUNT-1:0] dma_data_ready_o                    ,
    input  logic [127:0]                 dma_data_data_i  [DMA_CHANNEL_COUNT],
    input  logic [6:0]                   dma_data_free_i  [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] dma_data_valid_o                    ,
    output logic [127:0]                 dma_data_data_o                     
);

    logic trg_ack;

    assign trig_in_ack = {DMA_CHANNEL_COUNT{trg_ack}};

    logic [1:0]  state_sender  ;
    logic [1:0]  state_receiver;

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

    assign user_clk_o = user_clk;

    kdma_ila_0 u_ila (
        .clk    (user_clk ),

        .probe0 ('0      ),
        .probe1 ('0      ),
        .probe2 ('0      ),
        .probe3 (sys_rst ),
        .probe4 (tx_valid),
        .probe5 (tx_ready),
        .probe6 (tx_data ),
        .probe7 (rx_valid),
        .probe8 (rx_data ),
        .probe9 ({state_sender, state_receiver}),

        .trig_out     (  ),
        .trig_out_ack ('1),
        .trig_in      ('0),
        .trig_in_ack  (  )
    );

    logic                           dma_valid_arbed  ;
    logic                           dma_ready_arbed  ;
    logic [127:0]                   dma_data_arbed   ;
    logic [DMA_CHANNEL_COUNT_W-1:0] dma_channel_arbed;

    stream_arbiter #(
        .DATA_WIDTH (128              ),
        .INPUT_NUM  (DMA_CHANNEL_COUNT)
    ) u_stream_arbiter (
        .ACLK    (user_clk         ),
        .ARESETn (dma_rstn_i       ),

        .data_i  (dma_data_data_i  ),
        .valid_i (dma_data_valid_i ),
        .ready_o (dma_data_ready_o ),

        .data_o  (dma_data_arbed   ),
        .valid_o (dma_valid_arbed  ),
        .ready_i (dma_ready_arbed  ),
        .sel_o   (dma_channel_arbed)
    );

    kdma_aurora_sender #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_aurora_sender (
        .clk            (user_clk         ),
        .rst_n          (dma_rstn_i       ),

        .dma_valid_i    (dma_valid_arbed  ),
        .dma_ready_o    (dma_ready_arbed  ),
        .dma_data_i     (dma_data_arbed   ),
        .dma_channel_i  (dma_channel_arbed),

        .aurora_valid_o (tx_valid         ),
        .aurora_ready_i (tx_ready         ),
        .aurora_data_o  (tx_data          ),

        .state_o        (state_sender     )
    );

    kdma_aurora_receiver #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_aurora_receiver (
        .clk            (user_clk        ),
        .rst_n          (dma_rstn_i      ),

        .aurora_valid_i (rx_valid        ),
        .aurora_data_i  (rx_data         ),

        .dma_valid_o    (dma_data_valid_o),
        .dma_data_o     (dma_data_data_o ),

        .state_o        (state_receiver  )
    );

    kdma_aurora_64b66b_0 u_aurora (
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