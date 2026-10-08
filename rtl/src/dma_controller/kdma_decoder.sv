module kdma_decoder #(
    parameter DMA_CHANNEL_COUNT = 8 ,
    parameter DMA_OFFFSET_WIDTH = 22,
    parameter DMA_BYTES_WIDTH   = 22,

    parameter DMA_BURST_WIDTH         = DMA_BYTES_WIDTH - 4                                   ,
    parameter DMA_CHANNEL_COUNT_WIDTH = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT)
) (
    input  logic                               clk                                     ,
    input  logic                               rst_n                                   ,

    input  logic [21:0]                        bytecount_wr_data_i  [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        offset_wr_data_i     [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        bytecount_rd_data_i  [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        offset_rd_data_i     [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        bytecount_wr_biten_i [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        offset_wr_biten_i    [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        bytecount_rd_biten_i [DMA_CHANNEL_COUNT],
    input  logic [21:0]                        offset_rd_biten_i    [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0]       valid_i                                 ,
    output logic [DMA_CHANNEL_COUNT-1:0]       ready_o                                 ,

    output logic                               dma_task_valid_o                        ,
    input  logic                               dma_task_ready_i                        ,
    output logic [DMA_CHANNEL_COUNT_WIDTH-1:0] dma_task_channel_o                      ,
    output logic [DMA_BURST_WIDTH-1:0]         dma_task_burst_o                        ,
    output logic [DMA_OFFFSET_WIDTH-1:0]       dma_task_offset_o                       ,
    output logic                               dma_task_write_o                        
);

    logic [DMA_CHANNEL_COUNT_WIDTH-1:0] wr_decoded, rd_decoded;
    logic wr_valid, rd_valid;

    always_comb begin
        wr_decoded = '0;
        wr_valid = '0;
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            if (valid_i[i] && (&bytecount_wr_biten_i[i] && &offset_wr_biten_i[i])) begin
                wr_decoded = i;
                wr_valid = '1;
            end
        end
        
        rd_decoded = '0;
        rd_valid = '0;
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            if (valid_i[i] && (&bytecount_rd_biten_i[i] && &offset_rd_biten_i[i])) begin
                rd_decoded = i;
                rd_valid = '1;
            end
        end
    end

    typedef enum logic[1:0] {
        RESET         ,
        IDLE          ,
        GENERATE_DMAWR,
        GENERATE_DMARD
    } state_t;

    state_t state, state_next;

    logic [31:0] in_state_counter, in_state_counter_next;

    logic                               dma_task_valid  , dma_task_valid_next  ;
    logic [DMA_CHANNEL_COUNT_WIDTH-1:0] dma_task_channel, dma_task_channel_next;
    logic [DMA_BURST_WIDTH-1:0]         dma_task_burst  , dma_task_burst_next  ;
    logic [DMA_OFFFSET_WIDTH-1:0]       dma_task_offset , dma_task_offset_next ;
    logic                               dma_task_write  , dma_task_write_next  ;

    assign dma_task_valid_o   = dma_task_valid  ;
    assign dma_task_channel_o = dma_task_channel;
    assign dma_task_burst_o   = dma_task_burst  ;
    assign dma_task_offset_o  = dma_task_offset ;
    assign dma_task_write_o   = dma_task_write  ;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET;
            in_state_counter <= '0;

            dma_task_valid   <= '0;
            dma_task_channel <= '0;
            dma_task_burst   <= '0;
            dma_task_offset  <= '0;
            dma_task_write   <= '0;
        end
        else begin
            state <= state_next;

            dma_task_valid   <= dma_task_valid_next  ;
            dma_task_channel <= dma_task_channel_next;
            dma_task_burst   <= dma_task_burst_next  ;
            dma_task_offset  <= dma_task_offset_next ;
            dma_task_write   <= dma_task_write_next  ;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            RESET: begin
                state_next = IDLE;
            end
            IDLE: begin
                if (wr_valid) begin
                    state_next = GENERATE_DMAWR;
                end
                else if (rd_valid) begin
                    state_next = GENERATE_DMARD;
                end
                else begin
                    state_next = IDLE;
                end
            end
            GENERATE_DMAWR, GENERATE_DMARD: begin
                state_next = IDLE;
            end
            default: begin
                state_next = IDLE;
            end
        endcase
    end

    always_comb begin
        dma_task_valid_next   = dma_task_valid  ;
        dma_task_channel_next = dma_task_channel;
        dma_task_burst_next   = dma_task_burst  ;
        dma_task_offset_next  = dma_task_offset ;
        dma_task_write_next   = dma_task_write  ;

        ready_o = '0;

        case (state)
            RESET  : begin
            end
            IDLE: begin
                ready_o = valid_i;

                if (wr_valid) begin
                    dma_task_valid_next   = '1                                  ;
                    dma_task_channel_next = wr_decoded                          ;
                    dma_task_burst_next   = bytecount_wr_data_i[wr_decoded] >> 4;
                    dma_task_offset_next  = offset_wr_data_i   [wr_decoded]     ;
                    dma_task_write_next   = '1                                  ;
                end
                else if (rd_valid) begin
                    dma_task_valid_next   = '1                                  ;
                    dma_task_channel_next = rd_decoded                          ;
                    dma_task_burst_next   = bytecount_rd_data_i[rd_decoded] >> 4;
                    dma_task_offset_next  = offset_rd_data_i   [rd_decoded]     ;
                    dma_task_write_next   = '0                                  ;
                end
                else begin
                    dma_task_valid_next   = '0;
                end
            end
            GENERATE_DMAWR, GENERATE_DMARD: begin
                dma_task_valid_next = '0;
                ready_o = '0;
            end
            default: begin
            end
        endcase
    end
    
endmodule