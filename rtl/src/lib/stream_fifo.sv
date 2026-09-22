module stream_fifo #(
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 16,

    parameter ADDR_WIDTH = FIFO_DEPTH == 1 ? 1 : $clog2(FIFO_DEPTH)
) (
    input  logic                  ACLK   ,
    input  logic                  ARESETn,
    
    input  logic [DATA_WIDTH-1:0] data_i ,
    input  logic                  valid_i,
    output logic                  ready_o,
    output logic [ADDR_WIDTH:0]   free_o ,

    output logic [DATA_WIDTH-1:0] data_o ,
    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [ADDR_WIDTH:0]   count_o
);
    logic [DATA_WIDTH-1:0] fifo_mem [FIFO_DEPTH];

    logic we, re;
    logic fwft, fwft_next;
    logic lw, lw_next;
    
    logic [ADDR_WIDTH-1:0] read_ptr , read_ptr_next ;
    logic [ADDR_WIDTH-1:0] write_ptr, write_ptr_next;

    logic [ADDR_WIDTH:0] count_next;

    assign we = valid_i & ready_o;
    assign re = valid_o & ready_i | fwft | lw;

    assign valid_o = (count_o > 0) & ~fwft & ~lw;
    assign ready_o = (count_o < FIFO_DEPTH);

    assign free_o = FIFO_DEPTH - count_o;

    always_ff @(posedge ACLK or negedge ARESETn) begin : blockName
        if (!ARESETn) begin
            fwft      <= '0;
            read_ptr  <= '0;
            write_ptr <= '0;
            lw        <= '0;
            count_o   <= '0;
        end
        else begin
            fwft      <= fwft_next     ;
            read_ptr  <= read_ptr_next ;
            write_ptr <= write_ptr_next;
            lw        <= lw_next       ;
            count_o   <= count_next    ;
        end
    end


    always_comb begin
        read_ptr_next  = read_ptr ;
        write_ptr_next = write_ptr;
        count_next     = count_o  ;
        fwft_next      = fwft     ;
        lw_next        = lw       ;

        if (valid_i & ready_o) begin
            write_ptr_next = (write_ptr + 1 < FIFO_DEPTH) ? write_ptr + 1 : 0;
            count_next = count_o + 1;
            lw_next = '0;
            fwft_next = (count_o == 0) ? '1 : 0;
        end

        if (valid_o & ready_i) begin
            read_ptr_next = (read_ptr + 1 < FIFO_DEPTH) ? read_ptr + 1 : 0;
            count_next = count_next - 1;
            lw_next = (count_o == 1) ? '1 : 0;
            fwft_next = '0;
        end

        if (fwft) begin
            fwft_next = '0;
        end

        if (lw) begin
            lw_next = '0;
        end
    end

    always @(posedge ACLK) begin
        if (we) begin
            fifo_mem[write_ptr] <= data_i;
        end
    end

    always @(posedge ACLK) begin
        if (re) begin
            data_o <= fifo_mem[read_ptr_next];
        end
    end

endmodule