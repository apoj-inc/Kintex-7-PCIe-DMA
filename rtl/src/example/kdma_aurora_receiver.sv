module kdma_aurora_receiver #(
    parameter DMA_CHANNEL_COUNT = 8,

    parameter DMA_CHANNEL_COUNT_W = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT)
) (
    input  logic                         clk           ,
    input  logic                         rst_n         ,

    input  logic                         aurora_valid_i,
    input  logic [63:0]                  aurora_data_i ,

    output logic [DMA_CHANNEL_COUNT-1:0] dma_valid_o   ,
    output logic [127:0]                 dma_data_o    
);

    typedef enum logic [1:0] {
        RESET       ,
        RECEIVE_HDR ,
        RECEIVE_DATA
    } state_t;

    state_t state, state_next;

    logic                         aurora_hs_counter, aurora_hs_counter_next;
    logic [DMA_CHANNEL_COUNT_W:0] dma_channel      , dma_channel_next      ;
    logic [DMA_CHANNEL_COUNT-1:0] dma_valid        , dma_valid_next        ;
    logic [127:0]                 dma_data         , dma_data_next         ;

    assign dma_valid_o = dma_valid;
    assign dma_data_o  = dma_data ;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET;

            aurora_hs_counter <= '0;
            dma_channel       <= '0;
            dma_valid         <= '0;
            dma_data          <= '0;
        end
        else begin
            state <= state_next;
            
            aurora_hs_counter <= aurora_hs_counter_next;
            dma_channel       <= dma_channel_next      ;
            dma_valid         <= dma_valid_next        ;
            dma_data          <= dma_data_next         ;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            RESET        : begin
                state_next = RECEIVE_HDR;
            end
            RECEIVE_HDR  : begin
                if (aurora_valid_i) begin
                    state_next = RECEIVE_DATA;
                end
                else begin
                    state_next = state;
                end
            end
            RECEIVE_DATA : begin
                if (aurora_valid_i && aurora_hs_counter) begin
                    state_next = RECEIVE_HDR;
                end
                else begin
                    state_next = state;
                end
            end
            default      : begin
                state_next = RESET;
            end
        endcase
    end

    always_comb begin
        aurora_hs_counter_next = aurora_hs_counter;
        dma_channel_next       = dma_channel      ;
        dma_valid_next         = dma_valid        ;
        dma_data_next          = dma_data         ;

        case (state)
            RESET        : begin
                aurora_hs_counter_next = '0;
                dma_channel_next       = '0;
                dma_valid_next         = '0;
                dma_data_next          = '0;
            end
            RECEIVE_HDR  : begin
                dma_valid_next = '0;
                aurora_hs_counter_next = '0;

                if (aurora_valid_i) begin
                    dma_channel_next = aurora_data_i;
                end
            end
            RECEIVE_DATA : begin
                dma_data_next[7'(aurora_hs_counter) << 6 +: 64] = aurora_data_i                          ;
                dma_valid_next[dma_channel]                     = aurora_hs_counter ? aurora_valid_i : '0;

                if (aurora_valid_i) begin
                    aurora_hs_counter_next = aurora_hs_counter + 1;
                end
            end
            default   : begin
                
            end
        endcase
    end

endmodule