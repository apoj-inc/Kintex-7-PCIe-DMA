package kdma_pcie_headers_pkg;

    // {fmt, tp} decoder
    parameter RD_32 = 7'b0000000;
    parameter RD_64 = 7'b0100000;
    parameter WR_32 = 7'b1000000;
    parameter WR_64 = 7'b1100000;
    parameter CPL   = 7'b0001010;
    parameter CPLD  = 7'b1001010;

    // sts decoder
    parameter STS_SC  = 3'b000;
    parameter STS_UR  = 3'b001;
    parameter STS_CRS = 3'b010;
    parameter STS_CA  = 3'b100;

    typedef struct packed {
        logic        rsvd_2   ;
        logic [1:0]  fmt      ;
        logic [4:0]  tp       ;
        logic        rsvd_1   ;
        logic [2:0]  qos      ;
        logic [3:0]  rsvd_0   ;
        logic        digest   ;
        logic        err      ;
        logic [1:0]  attr     ;
        logic [1:0]  addr_tran;
        logic [9:0]  length   ;
    } header_dw0_t;

    typedef struct packed {
        // DW[2]
        logic [29:0] addr  ;
        logic [1:0]  rsvd  ;
        // DW[1]
        logic [15:0] req_id;
        logic [7:0]  tag   ;
        logic [3:0]  ldw_be;
        logic [3:0]  fdw_be;
    } memory_request_3dw_12_t;

    typedef struct packed {
        // DW[3]
        logic [29:0] addr_lo;
        logic [1:0]  rsvd   ;
        // DW[2]
        logic [31:0] addr_hi;
        // DW[1]
        logic [15:0] req_id ;
        logic [7:0]  tag    ;
        logic [3:0]  ldw_be ;
        logic [3:0]  fdw_be ;
    } memory_request_4dw_123_t;

    typedef struct packed {
        // DW[2]
        logic [15:0] req_id  ;
        logic [7:0]  tag     ;
        logic        rsvd    ;
        logic [6:0]  addr_lo ;
        // DW[1]
        logic [15:0] cpl_id  ;
        logic [2:0]  cpl_sts ;
        logic        bcm     ;
        logic [11:0] byte_cnt;
    } cpl_3dw_12_t;
    
endpackage