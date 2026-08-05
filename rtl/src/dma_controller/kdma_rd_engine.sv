module kdma_rd_engine #(
    parameter PIPELINE_CAPACITY = 4   ,

    parameter DMA_OFFFSET_WIDTH = 22  ,
    parameter DMA_BYTES_WIDTH   = 22  ,

    parameter DMA_RQ_DEPTH      = 1024,

    parameter DMA_BURST_WIDTH    = DMA_BYTES_WIDTH - 4                                            ,
    parameter DMA_TASK_WIDTH     = 1 + DMA_OFFFSET_WIDTH + DMA_BURST_WIDTH                        ,

    parameter R_BURST_COMPARATOR = (DMA_RQ_DEPTH - 1) < {6{1'b1}} ? (DMA_RQ_DEPTH - 1) : {6{1'b1}},

    parameter DMA_RQ_ADDR_WIDTH  = $clog2(DMA_RQ_DEPTH)                                           ,
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

    output logic                         dma_rddata_valid_o,
    input  logic                         dma_rddata_ready_i,
    input  logic [DMA_RQ_ADDR_WIDTH:0]   dma_rddata_free_i ,
    output logic [127:0]                 dma_rddata_data_o ,

    output logic                         arvalid_o         ,
    input  logic                         arready_i         ,
    output logic [63:0]                  araddr_o          ,
    output logic [7:0]                   arlen_o           ,
    output logic [AXI_ID_WIDTH-1:0]      arid_o            ,
    output logic [1:0]                   arburst_o         ,
    output logic [2:0]                   arsize_o          ,

    input  logic                         rvalid_i          ,
    output logic                         rready_o          ,
    input  logic [127:0]                 rdata_i           ,
    input  logic                         rlast_i           ,
    input  logic [1:0]                   rresp_i           ,
    input  logic [AXI_ID_WIDTH-1:0]      rid_i             ,

    output logic                         rd_irq_sts_o      ,
    input  logic                         rd_irq_clr_i      
);

    assign arburst_o = 2'b01 ;
    assign arsize_o  = 3'b100;

    typedef enum logic [2:0] {
        IDLE   ,
        AR     ,
        R      ,
        RD_IRQ 
    } state_t;

    typedef struct packed {
        logic [DMA_OFFFSET_WIDTH-1:0] offset           ;
        logic [DMA_BURST_WIDTH-1:0]   words_outstanding;
        logic [DMA_BURST_WIDTH-1:0]   words_left       ;
        logic [63:0]                  curr_addr        ;
        logic [7:0]                   curr_burst       ;
    } dmard_descriptor_t;
    
    state_t state, state_next;
    
    dmard_descriptor_t dmard_descriptor, dmard_descriptor_next;

    logic [AXI_ID_WIDTH-1:0] arid, arid_next;

    assign arid_o = arid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;

            dmard_descriptor <= '0;

            arid <= '0;
        end
        else begin
            state <= state_next;

            dmard_descriptor <= dmard_descriptor_next;

            arid <= arid_next;
        end
    end

    always_comb begin
        state_next = state;

        case (state)
            IDLE   : begin
                if (dma_task_valid_i && dma_task_ready_o) begin
                    state_next = AR;
                end
                else begin
                    state_next = IDLE;
                end
            end
            AR     : begin
                if (dmard_descriptor.words_left == '0) begin
                    state_next = R;
                end
                else begin
                    state_next = AR;
                end
            end
            R      : begin
                if (dmard_descriptor.words_outstanding == '0) begin
                    state_next = RD_IRQ;
                end
                else begin
                    state_next = R;
                end
            end
            RD_IRQ : begin
                if (rd_irq_clr_i == '1) begin
                    state_next = IDLE;
                end
                else begin
                    state_next = RD_IRQ;
                end
            end
            default: begin
                state_next = IDLE;
            end
        endcase
    end

    always_comb begin
        dma_task_ready_o = '0;

        dmard_descriptor_next = dmard_descriptor;
        
        arvalid_o = '0;
        araddr_o  = '0;
        arlen_o   = '0;
        arid_next = arid;

        rd_irq_sts_o = '0;

        case (state)
            IDLE   : begin
                if (dma_rddata_free_i >= dma_task_init_i) begin
                    dma_task_ready_o = '1;
                end
                else begin
                    dma_task_ready_o = '0;
                end

                if (dma_task_valid_i && dma_task_ready_o) begin
                    dmard_descriptor_next.offset            = dma_task_offset_i;
                    dmard_descriptor_next.words_outstanding = '0;
                    dmard_descriptor_next.words_left        = dma_task_burst_i;

                    dmard_descriptor_next.curr_addr         = dma_addr_i + dma_task_offset_i;
                    dmard_descriptor_next.curr_burst        = dma_task_init_i;
                    
                end
            end
            AR     : begin
                arvalid_o = (dmard_descriptor.words_left != '0) && ((dmard_descriptor.words_outstanding + dmard_descriptor.curr_burst) <= dma_rddata_free_i);
                araddr_o  = dmard_descriptor.curr_addr;
                arlen_o   = dmard_descriptor.curr_burst;

                if (arvalid_o && arready_i) begin
                    arid_next = (arid + 1 > PIPELINE_CAPACITY) ? 0 : arid + 1;

                    dmard_descriptor_next.words_outstanding = dmard_descriptor.words_outstanding + dmard_descriptor.curr_burst;
                    dmard_descriptor_next.words_left        = dmard_descriptor.words_left - (dmard_descriptor.curr_burst + 1);
                    dmard_descriptor_next.curr_addr         = dmard_descriptor.curr_addr + ((dmard_descriptor.curr_burst + 1) << 4);
                    dmard_descriptor_next.curr_burst        = ((dmard_descriptor.words_left - dmard_descriptor.curr_burst - 2) > R_BURST_COMPARATOR) ?
                                                            R_BURST_COMPARATOR : dmard_descriptor.words_left - dmard_descriptor.curr_burst - 2;
                end

                if (rvalid_i && rready_o) begin
                    dmard_descriptor_next.words_outstanding = dmard_descriptor_next.words_outstanding - 1;
                end
            end
            R      : begin
                if (rvalid_i && rready_o) begin
                    dmard_descriptor_next.words_outstanding = dmard_descriptor_next.words_outstanding - 1;
                end
            end
            RD_IRQ : begin
                dmard_descriptor_next.words_outstanding = '0;
                rd_irq_sts_o = '1;
            end
            default: begin
            end
        endcase
    end

    always_comb begin
        dma_rddata_valid_o = rvalid_i;
        rready_o = dma_rddata_ready_i;
        dma_rddata_data_o  = rdata_i ;
    end

endmodule