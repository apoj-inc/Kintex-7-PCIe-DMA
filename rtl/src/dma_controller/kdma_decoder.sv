module kdma_decoder #(
    parameter DMA_CHANNEL_COUNT = 8 ,
    parameter DMA_OFFFSET_WIDTH = 22,
    parameter DMA_BYTES_WIDTH   = 22,

    parameter DMA_BURST_WIDTH         = DMA_BYTES_WIDTH - 4                                   ,
    parameter DMA_CHANNEL_COUNT_WIDTH = DMA_CHANNEL_COUNT == 1 ? 1 : $clog2(DMA_CHANNEL_COUNT)
) (
    input  logic                               clk                                  ,
    input  logic                               rst_n                                ,

    input  logic [DMA_BYTES_WIDTH-1:0]         bytecount_wr_i    [DMA_CHANNEL_COUNT],
    input  logic [DMA_OFFFSET_WIDTH-1:0]       offset_wr_i       [DMA_CHANNEL_COUNT],
    input  logic [DMA_BYTES_WIDTH-1:0]         bytecount_rd_i    [DMA_CHANNEL_COUNT],
    input  logic [DMA_OFFFSET_WIDTH-1:0]       offset_rd_i       [DMA_CHANNEL_COUNT],
    input  logic [DMA_CHANNEL_COUNT-1:0]       btcnt_wr_swmod_i                     ,
    input  logic [DMA_CHANNEL_COUNT-1:0]       ofst_wr_swmod_i                      ,
    input  logic [DMA_CHANNEL_COUNT-1:0]       btcnt_rd_swmod_i                     ,
    input  logic [DMA_CHANNEL_COUNT-1:0]       ofst_rd_swmod_i                      ,

    output logic                               dma_task_valid_o                     ,
    input  logic                               dma_task_ready_i                     ,
    output logic [DMA_CHANNEL_COUNT_WIDTH-1:0] dma_task_channel_o                   ,
    output logic [DMA_BURST_WIDTH-1:0]         dma_task_burst_o                     ,
    output logic [DMA_OFFFSET_WIDTH-1:0]       dma_task_offset_o                    ,
    output logic                               dma_task_write_o                     
);

    logic [DMA_CHANNEL_COUNT_WIDTH-1:0] wr_decoded, rd_decoded;

    logic [DMA_CHANNEL_COUNT-1:0] btcnt_wr_swmod_ff;
    logic [DMA_CHANNEL_COUNT-1:0] ofst_wr_swmod_ff ;
    logic [DMA_CHANNEL_COUNT-1:0] btcnt_rd_swmod_ff;
    logic [DMA_CHANNEL_COUNT-1:0] ofst_rd_swmod_ff ;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btcnt_wr_swmod_ff <= '0;
            ofst_wr_swmod_ff  <= '0;
            btcnt_rd_swmod_ff <= '0;
            ofst_rd_swmod_ff  <= '0;
        end
        else begin
            btcnt_wr_swmod_ff <= btcnt_wr_swmod_i;
            ofst_wr_swmod_ff  <= ofst_wr_swmod_i ;
            btcnt_rd_swmod_ff <= btcnt_rd_swmod_i;
            ofst_rd_swmod_ff  <= ofst_rd_swmod_i ;
        end
    end

    always_comb begin
        wr_decoded = '0;
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            if (btcnt_wr_swmod_ff[i] && ofst_wr_swmod_ff) begin
                wr_decoded |= i;
            end
        end
        
        rd_decoded = '0;
        for (int i = 0; i < DMA_CHANNEL_COUNT; i++) begin
            if (btcnt_rd_swmod_ff[i] && ofst_rd_swmod_ff) begin
                rd_decoded |= i;
            end
        end
    end

    typedef enum logic[1:0] { 
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
            state <= IDLE;
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
            IDLE: begin
                if (btcnt_wr_swmod_ff & ofst_wr_swmod_ff) begin
                    state_next = GENERATE_DMAWR;
                end
                else if (btcnt_rd_swmod_ff & ofst_rd_swmod_ff) begin
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

        case (state)
            IDLE: begin
                if (btcnt_wr_swmod_ff & ofst_wr_swmod_ff) begin
                    dma_task_valid_next   = '1                             ;
                    dma_task_channel_next = wr_decoded                     ;
                    dma_task_burst_next   = bytecount_wr_i[wr_decoded] >> 4;
                    dma_task_offset_next  = offset_wr_i   [wr_decoded]     ;
                    dma_task_write_next   = '1                             ;
                end
                else if (btcnt_rd_swmod_ff & ofst_rd_swmod_ff) begin
                    dma_task_valid_next   = '1                             ;
                    dma_task_channel_next = rd_decoded                     ;
                    dma_task_burst_next   = bytecount_rd_i[rd_decoded] >> 4;
                    dma_task_offset_next  = offset_rd_i   [rd_decoded]     ;
                    dma_task_write_next   = '0                             ;
                end
                else begin
                    dma_task_valid_next   = '0;
                end
            end
            GENERATE_DMAWR, GENERATE_DMARD: begin
                dma_task_valid_next = '0;
            end
            default: begin
            end
        endcase
    end
    
endmodule