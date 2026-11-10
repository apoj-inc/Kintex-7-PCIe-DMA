module kdma_aurora_sender #(
    parameter DMA_CHANNEL_COUNT = 8,

    parameter DMA_CHANNEL_COUNT_W = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT)
) (
    input  logic                           clk           ,
    input  logic                           rst_n         ,

    input  logic                           dma_valid_i   ,
    output logic                           dma_ready_o   ,
    input  logic [127:0]                   dma_data_i    ,
    input  logic [DMA_CHANNEL_COUNT_W-1:0] dma_channel_i ,

    output logic                           aurora_valid_o,
    input  logic                           aurora_ready_i,
    output logic [63:0]                    aurora_data_o ,

    output logic [1:0]                     state_o       
);

    typedef enum logic [1:0] {
        RESET    ,
        SEND_HDR ,
        SEND_DATA
    } state_t;

    state_t state, state_next;
    logic aurora_hs_counter, aurora_hs_counter_next;

    assign state_o = state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET;

            aurora_hs_counter <= '0;
        end
        else begin
            state <= state_next;
            
            aurora_hs_counter <= aurora_hs_counter_next;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            RESET     : begin
                state_next = SEND_HDR;
            end
            SEND_HDR  : begin
                if (aurora_valid_o && aurora_ready_i) begin
                    state_next = SEND_DATA;
                end
                else begin
                    state_next = state;
                end
            end
            SEND_DATA : begin
                if (dma_valid_i && dma_ready_o) begin
                    state_next = SEND_HDR;
                end
                else begin
                    state_next = state;
                end
            end
            default   : begin
                state_next = RESET;
            end
        endcase
    end

    always_comb begin
        dma_ready_o    = '0;
        aurora_valid_o = '0;
        aurora_data_o  = '0;
        
        aurora_hs_counter_next = aurora_hs_counter;

        case (state)
            RESET     : begin
                dma_ready_o            = '0;
                aurora_valid_o         = '0;
                aurora_data_o          = '0;
                aurora_hs_counter_next = '0;
            end
            SEND_HDR  : begin
                if (dma_valid_i) begin
                    aurora_valid_o = '1           ;
                    aurora_data_o  = dma_channel_i;
                end
            end
            SEND_DATA : begin
                aurora_valid_o = '1                                          ;
                aurora_data_o  = dma_data_i[7'(aurora_hs_counter) << 6 +: 64];
                dma_ready_o    = aurora_hs_counter == 1 ? aurora_ready_i : '0;

                if (aurora_valid_o && aurora_ready_i) begin
                    aurora_hs_counter_next = aurora_hs_counter + 1;
                end
            end
            default   : begin
                
            end
        endcase
    end

endmodule