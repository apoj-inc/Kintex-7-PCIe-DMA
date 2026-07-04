package kdma_pcie_headers;

    typedef struct packed {
        logic        rsvd_3;
        logic [1:0]  fmt   ;
        logic [4:0]  tp    ;
        logic        rsvd_2;
        logic [2:0]  qos   ;
        logic [3:0]  rsvd_1;
        logic        digest;
        logic        err   ;
        logic [1:0]  attr  ;
        logic [1:0]  rsvd_0;
        logic [9:0]  length;
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
        logic [7:0]  cpl_sts ;
        logic        bcm     ;
        logic [6:0]  byte_cnt;
    } cpl_3dw_12_t;
    
endpackage