module kdma_pcie_stream_reshuffle (
    input  logic         clk                  ,
    input  logic         rst_n                ,

    input  logic         pcie_valid_i         ,
    output logic         pcie_ready_o         ,
    input  logic [127:0] pcie_data_i          ,
    input  logic [4:0]   pcie_sof_i           ,
    input  logic [4:0]   pcie_eof_i           ,
    input  logic [7:0]   pcie_bar_hit_i       ,

    output logic         pcie_detach_valid_o  ,
    input  logic         pcie_detach_ready_i  ,
    output logic [127:0] pcie_detach_data_o   ,
    output logic         pcie_detach_header_o ,
    output logic [7:0]   pcie_detach_bar_hit_o,
    output logic [4:0]   pcie_detach_eof_o    
);

    logic         pcie_destr_valid_wr  , pcie_destr_valid_rd  ;
    logic         pcie_destr_ready_wr  , pcie_destr_ready_rd  ;
    logic [127:0] pcie_destr_data_wr   , pcie_destr_data_rd   ;
    logic [7:0]   pcie_destr_bar_hit_wr, pcie_destr_bar_hit_rd;
    logic [4:0]   pcie_destr_eof_wr    , pcie_destr_eof_rd    ;

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

        .data_o  ({pcie_destr_data_rd, pcie_destr_bar_hit_rd, pcie_destr_eof_rd}),
        .valid_o (pcie_destr_valid_rd),
        .ready_i (pcie_destr_ready_rd)
    );

    kdma_pcie_header_detacher u_kdma_pcie_header_detacher (
        .clk                   (clk                  ),
        .rst_n                 (rst_n                ),

        .pcie_destr_valid_i    (pcie_destr_valid_rd  ),
        .pcie_destr_ready_o    (pcie_destr_ready_rd  ),
        .pcie_destr_data_i     (pcie_destr_data_rd   ),
        .pcie_destr_bar_hit_i  (pcie_destr_bar_hit_rd),
        .pcie_destr_eof_i      (pcie_destr_eof_rd    ),

        .pcie_detach_valid_o   (pcie_detach_valid_o  ),
        .pcie_detach_ready_i   (pcie_detach_ready_i  ),
        .pcie_detach_data_o    (pcie_detach_data_o   ),
        .pcie_detach_header_o  (pcie_detach_header_o ),
        .pcie_detach_bar_hit_o (pcie_detach_bar_hit_o),
        .pcie_detach_eof_o     (pcie_detach_eof_o    )
    );
    
endmodule