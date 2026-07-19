module kdma_axis_interconnect #(
    parameter DMA_CHANNEL_COUNT = 8
) (
    input  logic                          clk                                      ,
    input  logic                          rst_n                                    ,

    input  logic                          bar_resp_pcie_valid_i                    ,
    output logic                          bar_resp_pcie_ready_o                    ,
    input  logic [127:0]                  bar_resp_pcie_data_i                     ,
    input  logic [15:0]                   bar_resp_pcie_tkeep_i                    ,
    input  logic                          bar_resp_pcie_tlast_i                    ,

    input  logic [DMA_CHANNEL_COUNT-1:0]  dmard_pcie_valid_i                       ,
    output logic [DMA_CHANNEL_COUNT-1:0]  dmard_pcie_ready_o                       ,
    input  logic [127:0]                  dmard_pcie_data_i     [DMA_CHANNEL_COUNT],
    input  logic [15:0]                   dmard_pcie_tkeep_i    [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0]  dmard_pcie_tlast_i                       ,

    input  logic [DMA_CHANNEL_COUNT-1:0]  dmawr_pcie_valid_i                       ,
    output logic [DMA_CHANNEL_COUNT-1:0]  dmawr_pcie_ready_o                       ,
    input  logic [127:0]                  dmawr_pcie_data_i     [DMA_CHANNEL_COUNT],
    input  logic [15:0]                   dmawr_pcie_tkeep_i    [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0]  dmawr_pcie_tlast_i                       ,
    
    output logic                          pcie_valid_o                             ,
    input  logic                          pcie_ready_i                             ,
    output logic [127:0]                  pcie_data_o                              ,
    output logic [15:0]                   pcie_tkeep_o                             ,
    output logic                          pcie_tlast_o                             
);

    logic [128+16-1:0]            dmard_pcie_data_wr  [DMA_CHANNEL_COUNT];
    logic [128+16-1:0]            dmawr_pcie_data_wr  [DMA_CHANNEL_COUNT];

    generate
        genvar i;

        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : repack_wires
            assign dmard_pcie_data_wr[i] = {dmard_pcie_data_i[i], dmard_pcie_tkeep_i[i]};
            assign dmawr_pcie_data_wr[i] = {dmawr_pcie_data_i[i], dmawr_pcie_tkeep_i[i]};
        end
    endgenerate

    logic              dmard_pcie_valid_rd, dmawr_pcie_valid_rd;
    logic              dmard_pcie_ready_rd, dmawr_pcie_ready_rd;
    logic              dmard_pcie_tlast_rd, dmawr_pcie_tlast_rd;
    logic [128+16-1:0] dmard_pcie_data_rd , dmawr_pcie_data_rd ;
    
    logic [2:0]        final_pcie_valid_wr    ;
    logic [2:0]        final_pcie_ready_wr    ;
    logic [128+16-1:0] final_pcie_data_wr  [3];
    logic [2:0]        final_pcie_tlast_wr    ;

    assign final_pcie_valid_wr[0] = dmard_pcie_valid_rd;
    assign dmard_pcie_ready_rd = final_pcie_ready_wr[0];
    assign final_pcie_tlast_wr[0] = dmard_pcie_tlast_rd;
    assign final_pcie_data_wr [0] = dmard_pcie_data_rd ;

    assign final_pcie_valid_wr[1] = dmawr_pcie_valid_rd;
    assign dmawr_pcie_ready_rd = final_pcie_ready_wr[1];
    assign final_pcie_tlast_wr[1] = dmawr_pcie_tlast_rd;
    assign final_pcie_data_wr [1] = dmawr_pcie_data_rd ;

    assign final_pcie_valid_wr[2] = bar_resp_pcie_valid_i;
    assign bar_resp_pcie_ready_o = final_pcie_ready_wr[2];
    assign final_pcie_tlast_wr[2] = bar_resp_pcie_tlast_i;
    assign final_pcie_data_wr [2] = {bar_resp_pcie_data_i, bar_resp_pcie_tkeep_i};

    hs_wrmhl_arbiter #(
        .DATA_WIDTH (128+16           ),
        .INPUT_NUM  (DMA_CHANNEL_COUNT)
    ) u_hs_wrmhl_arbiter_dmard (
        .clk     (clk  ),
        .rst_n   (rst_n),

        .valid_i (dmard_pcie_valid_i),
        .ready_o (dmard_pcie_ready_o),
        .data_i  (dmard_pcie_data_wr),
        .last_i  (dmard_pcie_tlast_i),

        .valid_o (dmard_pcie_valid_rd),
        .ready_i (dmard_pcie_ready_rd),
        .data_o  (dmard_pcie_data_rd),
        .last_o  (dmard_pcie_tlast_rd),

        .sel_o   ()
    );
    
    hs_wrmhl_arbiter #(
        .DATA_WIDTH (128+16           ),
        .INPUT_NUM  (DMA_CHANNEL_COUNT)
    ) u_hs_wrmhl_arbiter_dmawr (
        .clk     (clk  ),
        .rst_n   (rst_n),

        .valid_i (dmawr_pcie_valid_i),
        .ready_o (dmawr_pcie_ready_o),
        .data_i  (dmawr_pcie_data_wr),
        .last_i  (dmawr_pcie_tlast_i),

        .valid_o (dmawr_pcie_valid_rd),
        .ready_i (dmawr_pcie_ready_rd),
        .data_o  (dmawr_pcie_data_rd ),
        .last_o  (dmawr_pcie_tlast_rd),

        .sel_o   ()
    );
    
    hs_wrmhl_arbiter #(
        .DATA_WIDTH (128+16),
        .INPUT_NUM  (3     )
    ) u_hs_wrmhl_arbiter_final (
        .clk     (clk  ),
        .rst_n   (rst_n),

        .valid_i (final_pcie_valid_wr),
        .ready_o (final_pcie_ready_wr),
        .data_i  (final_pcie_data_wr ),
        .last_i  (final_pcie_tlast_wr),

        .valid_o (pcie_valid_o),
        .ready_i (pcie_ready_i),
        .data_o  ({pcie_data_o, pcie_tkeep_o}),
        .last_o  (pcie_tlast_o),

        .sel_o   ()
    );

endmodule