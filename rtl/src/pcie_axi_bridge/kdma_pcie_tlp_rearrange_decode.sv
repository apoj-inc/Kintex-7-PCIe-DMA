module kdma_pcie_tlp_rearrange_decode #(
    parameter BAR_COUNT         = 6,

    parameter DMA_CHANNEL_COUNT = 8,
    parameter PIPELINE_CAPACITY = 4,

    parameter TOTAL_ID_COUNT = DMA_CHANNEL_COUNT * PIPELINE_CAPACITY
) (
    input  logic                      clk                          ,
    input  logic                      rst_n                        ,

    input  logic                      pcie_valid_i                 ,
    output logic                      pcie_ready_o                 ,
    input  logic [127:0]              pcie_data_i                  ,
    input  logic [4:0]                pcie_sof_i                   ,
    input  logic [4:0]                pcie_eof_i                   ,
    input  logic [7:0]                pcie_bar_hit_i               ,

    output logic [BAR_COUNT-1:0]      bar_psel_o                   ,
    output logic                      bar_penable_o                ,
    input  logic [BAR_COUNT-1:0]      bar_pready_i                 ,
    output logic [63:0]               bar_paddr_o                  ,
    output logic                      bar_pwrite_o                 ,
    output logic [127:0]              bar_pwdata_o                 ,
    output logic [15:0]               bar_pstrb_o                  ,
    input  logic [127:0]              bar_prdata_i      [BAR_COUNT],

    output logic [TOTAL_ID_COUNT-1:0] dmard_valid_o                ,
    input  logic [TOTAL_ID_COUNT-1:0] dmard_ready_i                ,
    output logic [127:0]              dmard_data_o                 ,
    output logic                      dmard_last_o                 ,

    output logic                      pcie_valid_o                 ,
    input  logic                      pcie_ready_i                 ,
    output logic [127:0]              pcie_data_o                  ,
    output logic [15:0]               pcie_tkeep_o                 ,
    output logic                      pcie_tlast_o                 ,

    input  logic [7:0]                bus_number_i                 ,
    input  logic [4:0]                device_number_i              ,
    input  logic [2:0]                function_number_i            ,

    output logic                      error_o                      
);

    logic         pcie_destr_valid_wr  , pcie_destr_valid_rd  ;
    logic         pcie_destr_ready_wr  , pcie_destr_ready_rd  ;
    logic [127:0] pcie_destr_data_wr   , pcie_destr_data_rd   ;
    logic [7:0]   pcie_destr_bar_hit_wr, pcie_destr_bar_hit_rd;
    logic [4:0]   pcie_destr_eof_wr    , pcie_destr_eof_rd    ;

    logic         pcie_detach_valid  ;
    logic         pcie_detach_ready  ;
    logic [127:0] pcie_detach_data   ;
    logic         pcie_detach_header ;
    logic [7:0]   pcie_detach_bar_hit;
    logic [4:0]   pcie_detach_eof    ;

    kdma_pcie_destraddle u_kdma_pcie_destraddle (
        .clk                  (clk                  ),
        .rst_n                (rst_n                ),

        .pcie_valid_i         (pcie_valid_i         ),
        .pcie_ready_o         (pcie_ready_o         ),
        .pcie_data_i          (pcie_data_i          ),
        .pcie_sof_i           (pcie_sof_i           ),
        .pcie_eof_i           (pcie_eof_i           ),
        .pcie_bar_hit_i       (pcie_bar_hit_i       ),

        .pcie_destr_valid_o   (pcie_destr_valid_wr  ),
        .pcie_destr_ready_i   (pcie_destr_ready_wr  ),
        .pcie_destr_data_o    (pcie_destr_data_wr   ),
        .pcie_destr_bar_hit_o (pcie_destr_bar_hit_wr),
        .pcie_destr_eof_o     (pcie_destr_eof_wr    )
    );

    stream_fifo #(
        .DATA_WIDTH (128 + 8 + 5),
        .FIFO_DEPTH (2 )
    ) skid (
        .ACLK    (clk  ),
        .ARESETn (rst_n),

        .data_i  ({pcie_destr_data_wr, pcie_destr_bar_hit_wr, pcie_destr_eof_wr}),
        .valid_i (pcie_destr_valid_wr),
        .ready_o (pcie_destr_ready_wr),
        .free_o  (),

        .data_o  ({pcie_destr_data_rd, pcie_destr_bar_hit_rd, pcie_destr_eof_rd}),
        .valid_o (pcie_destr_valid_rd),
        .ready_i (pcie_destr_ready_rd),
        .count_o ()
    );

    kdma_pcie_header_detacher u_kdma_pcie_header_detacher (
        .clk                   (clk                  ),
        .rst_n                 (rst_n                ),

        .pcie_destr_valid_i    (pcie_destr_valid_rd  ),
        .pcie_destr_ready_o    (pcie_destr_ready_rd  ),
        .pcie_destr_data_i     (pcie_destr_data_rd   ),
        .pcie_destr_bar_hit_i  (pcie_destr_bar_hit_rd),
        .pcie_destr_eof_i      (pcie_destr_eof_rd    ),

        .pcie_detach_valid_o   (pcie_detach_valid  ),
        .pcie_detach_ready_i   (pcie_detach_ready  ),
        .pcie_detach_data_o    (pcie_detach_data   ),
        .pcie_detach_header_o  (pcie_detach_header ),
        .pcie_detach_bar_hit_o (pcie_detach_bar_hit),
        .pcie_detach_eof_o     (pcie_detach_eof    )
    );

    kdma_pcie_tlp_decoder #(
        .BAR_COUNT         (BAR_COUNT        ),

        .DMA_CHANNEL_COUNT (DMA_CHANNEL_COUNT),
        .PIPELINE_CAPACITY (PIPELINE_CAPACITY)
    ) u_kdma_pcie_tlp_decoder (
        .clk                   (clk                ),
        .rst_n                 (rst_n              ),

        .pcie_detach_valid_i   (pcie_detach_valid  ),
        .pcie_detach_ready_o   (pcie_detach_ready  ),
        .pcie_detach_data_i    (pcie_detach_data   ),
        .pcie_detach_header_i  (pcie_detach_header ),
        .pcie_detach_bar_hit_i (pcie_detach_bar_hit),
        .pcie_detach_eof_i     (pcie_detach_eof    ),

        .bar_psel_o            (bar_psel_o         ),
        .bar_penable_o         (bar_penable_o      ),
        .bar_pready_i          (bar_pready_i       ),
        .bar_paddr_o           (bar_paddr_o        ),
        .bar_pwrite_o          (bar_pwrite_o       ),
        .bar_pwdata_o          (bar_pwdata_o       ),
        .bar_pstrb_o           (bar_pstrb_o        ),
        .bar_prdata_i          (bar_prdata_i       ),

        .dmard_valid_o         (dmard_valid_o      ),
        .dmard_ready_i         (dmard_ready_i      ),
        .dmard_data_o          (dmard_data_o       ),
        .dmard_last_o          (dmard_last_o       ),

        .pcie_valid_o          (pcie_valid_o       ),
        .pcie_ready_i          (pcie_ready_i       ),
        .pcie_data_o           (pcie_data_o        ),
        .pcie_tkeep_o          (pcie_tkeep_o       ),
        .pcie_tlast_o          (pcie_tlast_o       ),

        .bus_number_i          (bus_number_i       ),
        .device_number_i       (device_number_i    ),
        .function_number_i     (function_number_i  ),

        .error_o               (error_o            )
    );
    
endmodule
