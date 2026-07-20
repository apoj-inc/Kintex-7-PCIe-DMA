module kdma_pcie_axi_bridge #(
    parameter BAR_COUNT         = 6  ,

    parameter DMA_CHANNEL_COUNT = 8  ,
    parameter PIPELINE_CAPACITY = 4  ,

    parameter AXI_ADDR_WIDTH    = 64 ,
    parameter AXI_DATA_WIDTH    = 128,

    parameter TOTAL_ID_COUNT = DMA_CHANNEL_COUNT * PIPELINE_CAPACITY                 ,
    parameter AXI_ID_WIDTH   = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)
) (
    input  logic                         clk                                  ,
    input  logic                         rst_n                                ,

    input  logic                         pcie_valid_i                         ,
    output logic                         pcie_ready_o                         ,
    input  logic [127:0]                 pcie_data_i                          ,
    input  logic [4:0]                   pcie_sof_i                           ,
    input  logic [4:0]                   pcie_eof_i                           ,
    input  logic [7:0]                   pcie_bar_hit_i                       ,

    output logic                         pcie_valid_o                         ,
    input  logic                         pcie_ready_i                         ,
    output logic [127:0]                 pcie_data_o                          ,
    output logic [15:0]                  pcie_tkeep_o                         ,
    output logic                         pcie_tlast_o                         ,

    output logic [BAR_COUNT-1:0]         bar_psel_o                           ,
    output logic                         bar_penable_o                        ,
    input  logic [BAR_COUNT-1:0]         bar_pready_i                         ,
    output logic [63:0]                  bar_paddr_o                          ,
    output logic                         bar_pwrite_o                         ,
    output logic [127:0]                 bar_pwdata_o                         ,
    output logic [15:0]                  bar_pstrb_o                          ,
    input  logic [127:0]                 bar_prdata_i      [BAR_COUNT]        ,

    input  logic [DMA_CHANNEL_COUNT-1:0] arvalid_i                            ,
    output logic [DMA_CHANNEL_COUNT-1:0] arready_o                            ,
    input  logic [AXI_ADDR_WIDTH-1:0]    araddr_i          [DMA_CHANNEL_COUNT],
    input  logic [7:0]                   arlen_i           [DMA_CHANNEL_COUNT],
    input  logic [AXI_ID_WIDTH-1:0]      arid_i            [DMA_CHANNEL_COUNT],
    input  logic [1:0]                   arburst_i         [DMA_CHANNEL_COUNT],
    input  logic [2:0]                   arsize_i          [DMA_CHANNEL_COUNT],

    output logic [DMA_CHANNEL_COUNT-1:0] rvalid_o                             ,
    input  logic [DMA_CHANNEL_COUNT-1:0] rready_i                             ,
    output logic [AXI_DATA_WIDTH-1:0]    rdata_o           [DMA_CHANNEL_COUNT],
    output logic [DMA_CHANNEL_COUNT-1:0] rlast_o                              ,
    output logic [2:0]                   rresp_o           [DMA_CHANNEL_COUNT],
    output logic [AXI_ID_WIDTH-1:0]      rid_o             [DMA_CHANNEL_COUNT],

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
    
    input  logic                         msix_awvalid_i                       ,
    output logic                         msix_awready_o                       ,
    input  logic [63:0]                  msix_awaddr_i                        ,
    input  logic [7:0]                   msix_awlen_i                         ,
    input  logic [AXI_ID_WIDTH-1:0]      msix_awid_i                          ,
    input  logic [1:0]                   msix_awburst_i                       ,
    input  logic [2:0]                   msix_awsize_i                        ,

    input  logic                         msix_wvalid_i                        ,
    output logic                         msix_wready_o                        ,
    input  logic [127:0]                 msix_wdata_i                         ,
    input  logic                         msix_wlast_i                         ,
    input  logic [15:0]                  msix_wstrb_i                         ,

    output logic                         msix_bvalid_o                        ,
    input  logic                         msix_bready_i                        ,
    output logic [AXI_ID_WIDTH-1:0]      msix_bid_o                           ,
    output logic [2:0]                   msix_bresp_o                         ,

    input  logic [7:0]                   bus_number_i                         ,
    input  logic [4:0]                   device_number_i                      ,
    input  logic [2:0]                   function_number_i                    

);

    logic [TOTAL_ID_COUNT-1:0] dmard_valid_wr;
    logic [TOTAL_ID_COUNT-1:0] dmard_ready_wr;
    logic [127:0]              dmard_data_wr;
    logic                      dmard_last_wr;

    logic [AXI_ID_WIDTH-1:0] fifo_mux_sel_o [DMA_CHANNEL_COUNT];
    logic                    fifo_gate_o    [DMA_CHANNEL_COUNT];

    logic         bar_resp_pcie_valid;
    logic         bar_resp_pcie_ready;
    logic [127:0] bar_resp_pcie_data ;
    logic [15:0]  bar_resp_pcie_tkeep;
    logic         bar_resp_pcie_tlast;

    logic [DMA_CHANNEL_COUNT-1:0] dmard_pcie_valid                    ;
    logic [DMA_CHANNEL_COUNT-1:0] dmard_pcie_ready                    ;
    logic [127:0]                 dmard_pcie_data  [DMA_CHANNEL_COUNT];
    logic [15:0]                  dmard_pcie_tkeep [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] dmard_pcie_tlast                    ;

    logic [DMA_CHANNEL_COUNT-1:0] dmawr_pcie_valid                    ;
    logic [DMA_CHANNEL_COUNT-1:0] dmawr_pcie_ready                    ;
    logic [127:0]                 dmawr_pcie_data  [DMA_CHANNEL_COUNT];
    logic [15:0]                  dmawr_pcie_tkeep [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] dmawr_pcie_tlast                    ;

    logic [DMA_CHANNEL_COUNT-1:0] rvalid_dma                    ;
    logic [DMA_CHANNEL_COUNT-1:0] rready_dma                    ;
    logic [127:0]                 rdata_dma  [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] rlast_dma                     ;
    logic [2:0]                   rresp_dma  [DMA_CHANNEL_COUNT];
    logic [AXI_ID_WIDTH-1:0]      rid_dma    [DMA_CHANNEL_COUNT];

    logic [DMA_CHANNEL_COUNT-1:0] rvalid_err                    ;
    logic [DMA_CHANNEL_COUNT-1:0] rready_err                    ;
    logic [127:0]                 rdata_err  [DMA_CHANNEL_COUNT];
    logic [DMA_CHANNEL_COUNT-1:0] rlast_err                     ;
    logic [2:0]                   rresp_err  [DMA_CHANNEL_COUNT];
    logic [AXI_ID_WIDTH-1:0]      rid_err    [DMA_CHANNEL_COUNT];

    logic [DMA_CHANNEL_COUNT-1:0] err_valid                    ;
    logic [DMA_CHANNEL_COUNT-1:0] err_ready                    ;
    logic [AXI_ID_WIDTH-1:0]      err_id    [DMA_CHANNEL_COUNT];
    logic [7:0]                   err_len   [DMA_CHANNEL_COUNT];

    generate
        genvar i;

        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : axi_r_mux
            logic [1:0]                    rvalid_wr    ;
            logic [1:0]                    rready_wr    ;
            logic [128+3+AXI_ID_WIDTH-1:0] rdata_wr  [2];
            logic [1:0]                    rlast_wr     ;

            assign rvalid_wr[0]  = rvalid_dma[i];
            assign rready_dma[i] = rready_wr[0] ;
            assign rlast_wr[0]   = rlast_dma[i] ;
            assign rdata_wr [0]  = {rdata_dma[i], rresp_dma[i], rid_dma[i]};
            
            assign rvalid_wr[1]  = rvalid_err[i];
            assign rready_err[i] = rready_wr[1] ;
            assign rlast_wr[1]   = rlast_err[i] ;
            assign rdata_wr [1]  = {rdata_err[i], rresp_err[i], rid_err[i]};

            hs_wrmhl_arbiter #(
                .DATA_WIDTH (128+3+AXI_ID_WIDTH),
                .INPUT_NUM  (2                 )
            ) u_hs_wrmhl_arbiter (
                .clk     (clk  ),
                .rst_n   (rst_n),

                .valid_i (rvalid_wr),
                .ready_o (rready_wr),
                .data_i  (rdata_wr ),
                .last_i  (rlast_wr ),

                .valid_o (rvalid_o[i]),
                .ready_i (rready_i[i]),
                .data_o  ({rdata_o[i], rresp_o[i], rid_o[i]}),
                .last_o  (rlast_o[i] ),

                .sel_o   ()
            );
        end
    endgenerate

    kdma_pcie_tlp_rearrange_decode #(
        .BAR_COUNT         (BAR_COUNT        ),

        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
        .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
    ) u_kdma_pcie_tlp_rearrange_decode (
        .clk               (clk                ),
        .rst_n             (rst_n              ),

        .pcie_valid_i      (pcie_valid_i       ),
        .pcie_ready_o      (pcie_ready_o       ),
        .pcie_data_i       (pcie_data_i        ),
        .pcie_sof_i        (pcie_sof_i         ),
        .pcie_eof_i        (pcie_eof_i         ),
        .pcie_bar_hit_i    (pcie_bar_hit_i     ),

        .bar_psel_o        (bar_psel_o         ),
        .bar_penable_o     (bar_penable_o      ),
        .bar_pready_i      (bar_pready_i       ),
        .bar_paddr_o       (bar_paddr_o        ),
        .bar_pwrite_o      (bar_pwrite_o       ),
        .bar_pwdata_o      (bar_pwdata_o       ),
        .bar_pstrb_o       (bar_pstrb_o        ),
        .bar_prdata_i      (bar_prdata_i       ),

        .dmard_valid_o     (dmard_valid_wr     ),
        .dmard_ready_i     (dmard_ready_wr     ),
        .dmard_data_o      (dmard_data_wr      ),
        .dmard_last_o      (dmard_last_wr      ),

        .pcie_valid_o      (bar_resp_pcie_valid),
        .pcie_ready_i      (bar_resp_pcie_ready),
        .pcie_data_o       (bar_resp_pcie_data ),
        .pcie_tkeep_o      (bar_resp_pcie_tkeep),
        .pcie_tlast_o      (bar_resp_pcie_tlast),

        .bus_number_i      (bus_number_i       ),
        .device_number_i   (device_number_i    ),
        .function_number_i (function_number_i  ),

        .error_o           (                   )                     
    );

    generate
        genvar j;
        
        for (i = 0; i < DMA_CHANNEL_COUNT; i++) begin : dmard_buffer
            logic [PIPELINE_CAPACITY-1:0] dmard_valid_rd                    ;
            logic [PIPELINE_CAPACITY-1:0] dmard_ready_rd                    ;
            logic [127:0]                 dmard_data_rd  [PIPELINE_CAPACITY];
            logic                         dmard_last_rd  [PIPELINE_CAPACITY];

            assign rvalid_dma[i] = fifo_gate_o[i] ? dmard_valid_rd[fifo_mux_sel_o[i]] : '0;
            assign rdata_dma[i]  = dmard_data_rd[fifo_mux_sel_o[i]];
            assign rlast_dma[i]  = dmard_last_rd[fifo_mux_sel_o[i]];
            assign rresp_dma[i]  = '0;
            assign rid_dma[i]    = fifo_mux_sel_o[i];
            
            assign dmard_ready_rd = 1'(fifo_gate_o[i] ? rready_dma[i] : '0) << fifo_mux_sel_o[i];

            for (j = 0; j < PIPELINE_CAPACITY; j++) begin : fifos
                stream_fifo #(
                    .DATA_WIDTH (128+1),
                    .FIFO_DEPTH (256  ) 
                ) u_stream_fifo_id_buf (
                    .ACLK    (clk  ),
                    .ARESETn (rst_n),
                    
                    .data_i  ({dmard_data_wr, dmard_last_wr}),
                    .valid_i (dmard_valid_wr[i*PIPELINE_CAPACITY + j]),
                    .ready_o (dmard_ready_wr[i*PIPELINE_CAPACITY + j]),
                    .free_o  (),

                    .data_o  ({dmard_data_rd[j], dmard_last_rd[j]}),
                    .valid_o (dmard_valid_rd[j]),
                    .ready_i (dmard_ready_rd[j]),
                    .count_o ()
                );
            end

            kdma_axi_err_responder #(
                .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
                .AXI_ID_WIDTH   (AXI_ID_WIDTH  )
            ) u_kdma_axi_err_responder (
                .clk         (clk          ),
                .rst_n       (rst_n        ),

                .err_valid_i (err_valid[i] ),
                .err_ready_o (err_ready[i] ),
                .err_id_i    (err_id   [i] ),
                .err_len_i   (err_len  [i] ),

                .rvalid_o    (rvalid_err[i]),
                .rready_i    (rready_err[i]),
                .rdata_o     (rdata_err [i]),
                .rlast_o     (rlast_err [i]),
                .rresp_o     (rresp_err [i]),
                .rid_o       (rid_err   [i])
            );
        end
    endgenerate

    kdma_dmard_pipeline_ctrl #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
        .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
    ) u_kdma_dmard_pipeline_ctrl (
        .clk                   (clk              ),
        .rst_n                 (rst_n            ),

        .arvalid_i             (arvalid_i        ),
        .arready_o             (arready_o        ),
        .araddr_i              (araddr_i         ),
        .arlen_i               (arlen_i          ),
        .arid_i                (arid_i           ),
        .arburst_i             (arburst_i        ),
        .arsize_i              (arsize_i         ),

        .err_valid_o           (err_valid        ),
        .err_ready_i           (err_ready        ),
        .err_id_o              (err_id           ),
        .err_len_o             (err_len          ),

        .fifo_mux_sel_o        (fifo_mux_sel_o   ),
        .fifo_gate_o           (fifo_gate_o      ),

        .id_fifo_snoop_valid_i (rvalid_dma       ),
        .id_fifo_snoop_ready_i (rready_dma       ),
        .id_fifo_snoop_last_i  (rlast_dma        ),

        .pcie_valid_o          (dmard_pcie_valid ),
        .pcie_ready_i          (dmard_pcie_ready ),
        .pcie_data_o           (dmard_pcie_data  ),
        .pcie_tkeep_o          (dmard_pcie_tkeep ),
        .pcie_tlast_o          (dmard_pcie_tlast ),

        .bus_number_i          (bus_number_i     ),
        .device_number_i       (device_number_i  ),
        .function_number_i     (function_number_i)
    );

    kdma_dmawr_sink #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
        .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
    ) u_kdma_dmawr_sink (
        .clk               (clk               ),
        .rst_n             (rst_n             ),

        .awvalid_i         (awvalid_i         ),
        .awready_o         (awready_o         ),
        .awaddr_i          (awaddr_i          ),
        .awlen_i           (awlen_i           ),
        .awid_i            (awid_i            ),
        .awburst_i         (awburst_i         ),
        .awsize_i          (awsize_i          ),

        .wvalid_i          (wvalid_i          ),
        .wready_o          (wready_o          ),
        .wdata_i           (wdata_i           ),
        .wlast_i           (wlast_i           ),
        .wstrb_i           (wstrb_i           ),

        .bvalid_o          (bvalid_o          ),
        .bready_i          (bready_i          ),
        .bid_o             (bid_o             ),
        .bresp_o           (bresp_o           ),

        .pcie_valid_o      (dmawr_pcie_valid  ),
        .pcie_ready_i      (dmawr_pcie_ready  ),
        .pcie_data_o       (dmawr_pcie_data   ),
        .pcie_tkeep_o      (dmawr_pcie_tkeep  ),
        .pcie_tlast_o      (dmawr_pcie_tlast  ),
        
        .bus_number_i      (bus_number_i      ),
        .device_number_i   (device_number_i   ),
        .function_number_i (function_number_i )
    );

    kdma_axis_interconnect #(
        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT)
    ) u_kdma_axis_interconnect (
        .clk                   (clk                   ),
        .rst_n                 (rst_n                 ),

        .bar_resp_pcie_valid_i (bar_resp_pcie_valid   ),
        .bar_resp_pcie_ready_o (bar_resp_pcie_ready   ),
        .bar_resp_pcie_data_i  (bar_resp_pcie_data    ),
        .bar_resp_pcie_tkeep_i (bar_resp_pcie_tkeep   ),
        .bar_resp_pcie_tlast_i (bar_resp_pcie_tlast   ),

        .dmard_pcie_valid_i    (dmard_pcie_valid      ),
        .dmard_pcie_ready_o    (dmard_pcie_ready      ),
        .dmard_pcie_data_i     (dmard_pcie_data       ),
        .dmard_pcie_tkeep_i    (dmard_pcie_tkeep      ),
        .dmard_pcie_tlast_i    (dmard_pcie_tlast      ),

        .dmawr_pcie_valid_i    (dmawr_pcie_valid      ),
        .dmawr_pcie_ready_o    (dmawr_pcie_ready      ),
        .dmawr_pcie_data_i     (dmawr_pcie_data       ),
        .dmawr_pcie_tkeep_i    (dmawr_pcie_tkeep      ),
        .dmawr_pcie_tlast_i    (dmawr_pcie_tlast      ),

        .pcie_valid_o          (pcie_valid_o          ),
        .pcie_ready_i          (pcie_ready_i          ),
        .pcie_data_o           (pcie_data_o           ),
        .pcie_tkeep_o          (pcie_tkeep_o          ),
        .pcie_tlast_o          (pcie_tlast_o          )
    );
    
endmodule