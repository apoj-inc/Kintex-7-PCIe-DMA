module kdma_wr_engine #(
    parameter PIPELINE_CAPACITY = 4   ,

    parameter DMA_OFFFSET_WIDTH = 22  ,
    parameter DMA_BYTES_WIDTH   = 22  ,

    parameter DMA_WQ_DEPTH      = 1024,

    parameter DMA_BURST_WIDTH    = DMA_BYTES_WIDTH - 4                                            ,
    parameter DMA_TASK_WIDTH     = 1 + DMA_OFFFSET_WIDTH + DMA_BURST_WIDTH                        ,

    parameter W_BURST_COMPARATOR = (DMA_WQ_DEPTH - 1) < {6{1'b1}} ? (DMA_WQ_DEPTH - 1) : {6{1'b1}},

    parameter DMA_WQ_ADDR_WIDTH  = $clog2(DMA_WQ_DEPTH)                                           ,
    parameter AXI_ID_WIDTH       = PIPELINE_CAPACITY == 1 ? 1 : $clog2(PIPELINE_CAPACITY)         
) (
    input  logic                         clk               ,
    input  logic                         rst_n             ,

    input  logic [63:0]                  dma_addr_i        ,

    input  logic                         dma_task_valid_i  ,
    output logic                         dma_task_ready_o  ,
    input  logic [DMA_BURST_WIDTH-1:0]   dma_task_burst_i  ,
    input  logic [DMA_OFFFSET_WIDTH-1:0] dma_task_offset_i ,
    input  logic [5:0]                   dma_task_init_i   ,

    input  logic                         dma_wrdata_valid_i,
    output logic                         dma_wrdata_ready_o,
    input  logic [DMA_WQ_ADDR_WIDTH:0]   dma_wrdata_count_i,
    input  logic [127:0]                 dma_wrdata_data_i ,

    output logic                         awvalid_o         ,
    input  logic                         awready_i         ,
    output logic [63:0]                  awaddr_o          ,
    output logic [7:0]                   awlen_o           ,
    output logic [AXI_ID_WIDTH-1:0]      awid_o            ,
    output logic [1:0]                   awburst_o         ,
    output logic [2:0]                   awsize_o          ,

    output logic                         wvalid_o          ,
    input  logic                         wready_i          ,
    output logic [127:0]                 wdata_o           ,
    output logic                         wlast_o           ,
    output logic [15:0]                  wstrb_o           ,

    input  logic                         bvalid_i          ,
    output logic                         bready_o          ,
    input  logic [AXI_ID_WIDTH-1:0]      bid_i             ,
    input  logic [1:0]                   bresp_i           ,

    output logic                         wr_irq_sts_o      ,
    input  logic                         wr_irq_clr_i      
);

    assign awid_o    = '0    ;
    assign awburst_o = 2'b10 ;
    assign awsize_o  = 3'b100;

    assign wstrb_o = '1;

    assign bready_o = '1;

    typedef enum logic [2:0] {
        IDLE   ,
        AW     ,
        W      ,
        WR_IRQ 
    } state_t;

    typedef struct packed {
        logic [DMA_OFFFSET_WIDTH-1:0] offset    ;
        logic [DMA_BURST_WIDTH-1:0]   words_left;
        logic [63:0]                  curr_addr ;
        logic [7:0]                   curr_burst;
    } dmawr_descriptor_t;
    
    dmawr_descriptor_t dmawr_descriptor, dmawr_descriptor_next;
    
    state_t state, state_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;

            dmawr_descriptor <= '0;
        end
        else begin
            state <= state_next;

            dmawr_descriptor <= dmawr_descriptor_next;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            IDLE   : begin
                if (dma_task_valid_i && dma_task_ready_o) begin
                    state_next = AW;
                end
                else begin
                    state_next = IDLE;
                end
            end
            AW     : begin
                if (awvalid_o && awready_i) begin
                    state_next = W;
                end
                else begin
                    state_next = AW;
                end
            end
            W      : begin
                if (wvalid_o && wready_i) begin
                    if (wlast_o) begin
                        if (dmawr_descriptor.words_left == 1) begin
                            state_next = WR_IRQ;
                        end
                        else begin
                            state_next = AW;
                        end
                    end
                    else begin
                        state_next = W;
                    end
                end
            end
            WR_IRQ : begin
                if (wr_irq_clr_i == '1) begin
                    state_next = IDLE;
                end
                else begin
                    state_next = WR_IRQ;
                end
            end
            default: begin
                state_next = IDLE;
            end
        endcase
    end

    always_comb begin
        dma_task_ready_o = '0;

        dmawr_descriptor_next = dmawr_descriptor;

        awvalid_o = '0;
        awaddr_o  = '0;
        awlen_o   = '0;

        wvalid_o = '0;
        wdata_o  = '0;
        wlast_o  = '0;
        
        dma_wrdata_ready_o = '0;

        wr_irq_sts_o = '0;

        case (state)
            IDLE   : begin
                if (dma_wrdata_count_i >= dma_task_init_i) begin
                    dma_task_ready_o = '1;
                end
                else begin
                    dma_task_ready_o = '0;
                end

                if (dma_task_valid_i && dma_task_ready_o) begin
                    dmawr_descriptor_next.offset     = dma_task_offset_i;
                    dmawr_descriptor_next.words_left = dma_task_burst_i;

                    dmawr_descriptor_next.curr_addr  = dma_addr_i + dma_task_offset_i;
                    dmawr_descriptor_next.curr_burst = dma_task_init_i;
                    
                end
            end
            AW     : begin
                awvalid_o = '1;
                awaddr_o  = dmawr_descriptor.curr_addr;
                awlen_o   = dmawr_descriptor.curr_burst;
            end
            W      : begin
                wvalid_o = dma_wrdata_valid_i;
                wdata_o  = dma_wrdata_data_i ;
                wlast_o  = (dmawr_descriptor.curr_burst == '0);

                dma_wrdata_ready_o = wready_i;

                if (wvalid_o && wready_i) begin
                    dmawr_descriptor_next.curr_addr = dmawr_descriptor.curr_addr + 16;
                    dmawr_descriptor_next.words_left = dmawr_descriptor.words_left - 1;

                    if (dmawr_descriptor.curr_burst == '0) begin
                        dmawr_descriptor_next.curr_burst = (dmawr_descriptor.words_left - 2 > W_BURST_COMPARATOR) ? W_BURST_COMPARATOR : dmawr_descriptor.words_left - 2;
                    end
                    else begin
                        dmawr_descriptor_next.curr_burst = dmawr_descriptor.curr_burst - 1;
                    end
                end
            end
            WR_IRQ : begin
                wr_irq_sts_o = '1;
            end
            default: begin
            end
        endcase
    end

endmodule