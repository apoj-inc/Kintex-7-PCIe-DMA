module kdma_toplevel (
    input  logic           clk_in_p   ,
    input  logic           clk_in_n   ,

    input  logic           sys_rst_n  ,

    output logic           pci_exp_tx0_p,
    output logic           pci_exp_tx0_n,
    output logic           pci_exp_tx1_p,
    output logic           pci_exp_tx1_n,
    output logic           pci_exp_tx2_p,
    output logic           pci_exp_tx2_n,
    output logic           pci_exp_tx3_p,
    output logic           pci_exp_tx3_n,

    input  logic           pci_exp_rx0_p,
    input  logic           pci_exp_rx0_n,
    input  logic           pci_exp_rx1_p,
    input  logic           pci_exp_rx1_n,
    input  logic           pci_exp_rx2_p,
    input  logic           pci_exp_rx2_n,
    input  logic           pci_exp_rx3_p,
    input  logic           pci_exp_rx3_n
);

parameter     BAR_COUNT                             = 4         ;

parameter     DMA_CHANNEL_COUNT                     = 2         ;
parameter     PIPELINE_CAPACITY                     = 4         ;

parameter     DMA_BYTES_WIDTH                       = 22        ;
parameter     DMA_OFFFSET_WIDTH                     = 22        ;

parameter int DMA_WORD_BYTES    [DMA_CHANNEL_COUNT] = '{2{64  }};
parameter int DMA_WQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{64  }};
parameter int DMA_RQ_DEPTH      [DMA_CHANNEL_COUNT] = '{2{64  }};
parameter     DMA_TQ_DEPTH                          = 2         ;

parameter     MAX_WQ_DEPTH                          = 64        ;
parameter     MAX_RQ_DEPTH                          = 64        ;

parameter AXI_ID_WIDTH   = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY);
parameter MSIX_COUNT     = DMA_CHANNEL_COUNT                                     ;

logic [3:0] pci_exp_txp;
logic [3:0] pci_exp_txn;
logic [3:0] pci_exp_rxp;
logic [3:0] pci_exp_rxn;

assign pci_exp_txp = {pci_exp_tx3_p, pci_exp_tx2_p, pci_exp_tx1_p, pci_exp_tx0_p};
assign pci_exp_txn = {pci_exp_tx3_n, pci_exp_tx2_n, pci_exp_tx1_n, pci_exp_tx0_n};
assign pci_exp_rxp = {pci_exp_rx3_p, pci_exp_rx2_p, pci_exp_rx1_p, pci_exp_rx0_p};
assign pci_exp_rxn = {pci_exp_rx3_n, pci_exp_rx2_n, pci_exp_rx1_n, pci_exp_rx0_n};

logic clk;
logic rst_n;

logic           user_clk_out    ;
logic           user_reset_out  ;
logic           user_resetn_out ;

logic           s_axis_tx_tready;
logic [127 : 0] s_axis_tx_tdata ;
logic [ 15 : 0] s_axis_tx_tkeep ;
logic           s_axis_tx_tlast ;
logic           s_axis_tx_tvalid;

logic [127 : 0] m_axis_rx_tdata ;
logic [15 : 0]  m_axis_rx_tkeep ;
logic           m_axis_rx_tlast ;
logic           m_axis_rx_tvalid;
logic           m_axis_rx_tready;
logic [21 : 0]  m_axis_rx_tuser ;

logic [4:0]     m_axis_sof    ;
logic [4:0]     m_axis_eof    ;
logic [4:0]     m_axis_bar_hit;

assign user_resetn_out = ~user_reset_out;

assign m_axis_sof     = m_axis_rx_tuser[14:10];
assign m_axis_eof     = m_axis_rx_tuser[21:17];
assign m_axis_bar_hit = m_axis_rx_tuser[9:2];

logic [7:0] cfg_bus_number     ;
logic [4:0] cfg_device_number  ;
logic [2:0] cfg_function_number;

IBUF   sys_reset_n_ibuf (.O(rst_n), .I(sys_rst_n));

IBUFDS_GTE2 refclk_ibuf (.O(clk), .ODIV2(), .I(clk_in_p), .CEB(1'b0), .IB(clk_in_n));


kdma_echodevice_bridged #(
    .BAR_COUNT         (BAR_COUNT         ),

    .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT ),
    .PIPELINE_CAPACITY (PIPELINE_CAPACITY ),

    .DMA_BYTES_WIDTH   (DMA_BYTES_WIDTH   ),
    .DMA_OFFFSET_WIDTH (DMA_OFFFSET_WIDTH ),

    .DMA_WORD_BYTES    (DMA_WORD_BYTES    ),
    .DMA_WQ_DEPTH      (DMA_WQ_DEPTH      ),
    .DMA_RQ_DEPTH      (DMA_RQ_DEPTH      ),
    .DMA_TQ_DEPTH      (DMA_TQ_DEPTH      ),

    .MAX_WQ_DEPTH      (MAX_WQ_DEPTH      ),
    .MAX_RQ_DEPTH      (MAX_RQ_DEPTH      )
) (
    .clk              (user_clk_out   ),
    .rst_n            (user_resetn_out),

    .pcie_valid_i     (m_axis_rx_tvalid),
    .pcie_ready_o     (m_axis_rx_tready),
    .pcie_data_i      (m_axis_rx_tdata ),
    .pcie_sof_i       (m_axis_sof      ),
    .pcie_eof_i       (m_axis_eof      ),
    .pcie_bar_hit_i   (m_axis_bar_hit  ),

    .pcie_valid_o     (s_axis_tx_tvalid),
    .pcie_ready_i     (s_axis_tx_tready),
    .pcie_data_o      (s_axis_tx_tdata ),
    .pcie_tkeep_o     (s_axis_tx_tkeep ),
    .pcie_tlast_o     (s_axis_tx_tlast ),

    .bus_number_i     (cfg_bus_number     ),
    .device_number_i  (cfg_device_number  ),
    .function_number_i(cfg_function_number),

    .user_irq_i (0)       
);

logic [3:0] pclk_sel_big_1, pclk_sel_big_2, pclk_sel_big_3;
logic       pclk_sel;

logic       mmcm_clk_buf;
logic       txoutclk_out;
logic       mmcm_lock;
logic       mmcm_fb     ;
logic       clk_125mhz, muxout  ;
logic       clk_250mhz  ;
logic       userclk1, userclk1_buf;
logic       userclk2, userclk2_buf;
logic       oobclk  ;
logic       dclk;
logic       mmcm_rst_n;

assign mmcm_rst_n = '1;

always_ff @(posedge muxout or negedge mmcm_rst_n) begin : blockName
    if (!mmcm_rst_n) begin
        pclk_sel_big_3 <= '0;
        pclk_sel_big_2 <= '0;
        pclk_sel       <= '0;
    end
    else begin
        pclk_sel_big_2 <= pclk_sel_big_1;
        pclk_sel_big_3 <= pclk_sel_big_2;

        if (&pclk_sel_big_3) begin
            pclk_sel <= '1;
        end
        else if (&(~pclk_sel_big_3)) begin
            pclk_sel <= '0;
        end
        else begin
            pclk_sel <= '1;
        end
    end
end

BUFG mmcm_in_buf
(
    //---------- Input ---------------------------------
    .I                          (txoutclk_out), 
    //---------- Output --------------------------------
    .O                          (mmcm_clk_buf)
);

MMCME2_ADV #
(
    .BANDWIDTH                  ("OPTIMIZED"),
    .CLKOUT4_CASCADE            ("FALSE"),
    .COMPENSATION               ("ZHOLD"),
    .STARTUP_WAIT               ("FALSE"),
    .DIVCLK_DIVIDE              (1),
    .CLKFBOUT_MULT_F            (10),  
    .CLKFBOUT_PHASE             (0.000),
    .CLKFBOUT_USE_FINE_PS       ("FALSE"),
    .CLKOUT0_DIVIDE_F           (8),                    
    .CLKOUT0_PHASE              (0.000),
    .CLKOUT0_DUTY_CYCLE         (0.500),
    .CLKOUT0_USE_FINE_PS        ("FALSE"),
    .CLKOUT1_DIVIDE             (4),                    
    .CLKOUT1_PHASE              (0.000),
    .CLKOUT1_DUTY_CYCLE         (0.500),
    .CLKOUT1_USE_FINE_PS        ("FALSE"),
    .CLKOUT2_DIVIDE             (4),                  
    .CLKOUT2_PHASE              (0.000),
    .CLKOUT2_DUTY_CYCLE         (0.500),
    .CLKOUT2_USE_FINE_PS        ("FALSE"),
    .CLKOUT3_DIVIDE             (8),                  
    .CLKOUT3_PHASE              (0.000),
    .CLKOUT3_DUTY_CYCLE         (0.500),
    .CLKOUT3_USE_FINE_PS        ("FALSE"),
    .CLKOUT4_DIVIDE             (20),                  
    .CLKOUT4_PHASE              (0.000),
    .CLKOUT4_DUTY_CYCLE         (0.500),
    .CLKOUT4_USE_FINE_PS        ("FALSE"),
    .CLKIN1_PERIOD              (10),                   
    .REF_JITTER1                (0.010)
    
) mmcm_i (
    .CLKIN1                     (mmcm_clk_buf),
    .CLKIN2                     (1'd0),      
    .CLKINSEL                   (1'd1),
    .CLKFBIN                    (mmcm_fb),
    .RST                        (1'd0),
    .PWRDWN                     (1'd0), 
    
    //---------- Output ------------------------------------
    .CLKFBOUT                   (mmcm_fb),
    .CLKOUT0                    (clk_125mhz),
    .CLKOUT1                    (clk_250mhz),
    .CLKOUT2                    (userclk1),
    .CLKOUT3                    (userclk2),
    .CLKOUT4                    (oobclk),
    .CLKOUT5                    (),
    .CLKOUT6                    (),
    .LOCKED                     (mmcm_lock)

);

BUFGCTRL pclk_i1
(
    //---------- Input ---------------------------------
    .CE0                        (1'd1),         
    .CE1                        (1'd1),        
    .I0                         (clk_125mhz),   
    .I1                         (clk_250mhz),   
    .IGNORE0                    (1'd0),        
    .IGNORE1                    (1'd0),        
    .S0                         (~pclk_sel),    
    .S1                         ( pclk_sel),    
    //---------- Output --------------------------------
    .O                          (muxout)
);

BUFG usr1 (.O(userclk1_buf), .I(userclk1));
BUFG usr2 (.O(userclk2_buf), .I(userclk2));
BUFG dclkbuf (.O(dclk), .I(clk_125mhz));

pcie_7x_0 u_pcie_7x_0 (
    .pci_exp_txp                  (pci_exp_txp)        ,
    .pci_exp_txn                  (pci_exp_txn)        ,
    .pci_exp_rxp                  (pci_exp_rxp)        ,
    .pci_exp_rxn                  (pci_exp_rxn)        ,
    .user_clk_out                 (user_clk_out)       ,
    .user_reset_out               (user_reset_out)     ,
    .s_axis_tx_tready             (s_axis_tx_tready)   ,
    .s_axis_tx_tdata              (s_axis_tx_tdata )   ,
    .s_axis_tx_tkeep              (s_axis_tx_tkeep )   ,
    .s_axis_tx_tlast              (s_axis_tx_tlast )   ,
    .s_axis_tx_tvalid             (s_axis_tx_tvalid)   ,
    .s_axis_tx_tuser              ('0)                 ,
    .m_axis_rx_tdata              (m_axis_rx_tdata )   ,
    .m_axis_rx_tkeep              (m_axis_rx_tkeep )   ,
    .m_axis_rx_tlast              (m_axis_rx_tlast )   ,
    .m_axis_rx_tvalid             (m_axis_rx_tvalid)   ,
    .m_axis_rx_tready             (m_axis_rx_tready)   ,
    .m_axis_rx_tuser              (m_axis_rx_tuser )   ,
    .sys_clk                      (clk)                ,
    .sys_rst_n                    (rst_n)              ,
    .cfg_bus_number               (cfg_bus_number     ),
    .cfg_device_number            (cfg_device_number  ),
    .cfg_function_number          (cfg_function_number),
    .cfg_interrupt                ('0                 ),
    .cfg_interrupt_assert         ('0                 ),
    .cfg_interrupt_di             ('0                 ),
    .cfg_interrupt_stat           ('0                 ),
    .cfg_pciecap_interrupt_msgnum ('0                 ),
    .pipe_txoutclk_out            (txoutclk_out       ),
    .pipe_pclk_sel_out            (pclk_sel_big_1     ),
    .pipe_pclk_in                 (muxout             ),
    .pipe_rxusrclk_in             (muxout             ),
    .pipe_rxoutclk_in             ('0                 ),
    .pipe_dclk_in                 (dclk               ),
    .pipe_userclk1_in             (userclk1_buf       ),
    .pipe_userclk2_in             (userclk2_buf       ),
    .pipe_oobclk_in               (muxout             ),
    .pipe_mmcm_lock_in            (mmcm_lock          ),
    .pipe_mmcm_rst_n              (mmcm_rst_n         )
);

endmodule