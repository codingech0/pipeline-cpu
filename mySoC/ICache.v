`timescale 1ns / 1ps

`include "defines.vh"

// 主存地址位宽：32bit
// Cache容量：1KB
// Cache块大小：128bit / 4 * 32bit = 4*4Byte
// Cache块个数：64

module ICache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active

    // Interface to CPU
    input  wire         inst_rreq,      // 来自CPU的取指请求
    input  wire [31:0]  inst_addr,      // 来自CPU的取指地址
    output wire         inst_ready,     // Cache可以在本拍接收新的取指请求
    output reg          inst_valid,     // 输出给CPU的指令有效信号（读指令命中）
    output reg  [31:0]  inst_out,       // 输出给CPU的指令

    // Interface to Read Bus
    input  wire         dev_rrdy,       // 主存就绪信号
    output reg  [ 3:0]  cpu_ren,        // 输出给主存的读使能信号
    output reg  [31:0]  cpu_raddr,      // 输出给主存的读地址
    input  wire         dev_rvalid,     // 来自主存的数据有效信号
    input  wire [127:0] dev_rdata       // 来自主存的读数据
);

`ifdef ENABLE_ICACHE    /******** 不要修改此行代码 ********/

    localparam [2:0] IDLE         = 3'd0;
    localparam [2:0] LOOKUP_WAIT  = 3'd1;
    localparam [2:0] TAG_CHECK    = 3'd2;
    localparam [2:0] REFILL_REQ   = 3'd3;
    localparam [2:0] REFILL_WAIT  = 3'd4;
    localparam [2:0] REFILL_SYNC  = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [31:0] req_addr;

    wire [4:0] req_tag     = req_addr[14:10];
    wire [1:0] word_offset = req_addr[3:2];
    wire [5:0] cache_index = req_addr[9:4];

    wire [133:0] cache_line_r;
    wire         cache_valid = cache_line_r[133];
    wire [4:0]   cache_tag   = cache_line_r[132:128];
    wire         cache_hit   =
        (cache_valid === 1'b1) && (cache_tag == req_tag);

    wire         cache_we =
        (state == REFILL_WAIT) && dev_rvalid;
    wire [133:0] cache_line_w =
        {1'b1, req_tag, dev_rdata};

    blk_mem_gen_1 U_isram (
        .clka   (cpu_clk),
        .wea    (cache_we),
        .addra  (cache_index),
        .dina   (cache_line_w),
        .douta  (cache_line_r)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            state    <= IDLE;
            req_addr <= 32'd0;
        end
        else begin
            state <= next_state;

            if ((state == IDLE) && inst_rreq) begin
                req_addr <= inst_addr;
            end
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (inst_rreq) begin
                    next_state = LOOKUP_WAIT;
                end
            end

            // req_addr is registered in IDLE. This state gives synchronous
            // Block RAM one rising edge to return the selected cache line.
            LOOKUP_WAIT: begin
                next_state = TAG_CHECK;
            end

            TAG_CHECK: begin
                if (cache_hit) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = REFILL_REQ;
                end
            end

            REFILL_REQ: begin
                if (dev_rrdy) begin
                    next_state = REFILL_WAIT;
                end
            end

            REFILL_WAIT: begin
                if (dev_rvalid) begin
                    next_state = REFILL_SYNC;
                end
            end

            // The refill is written on the REFILL_WAIT -> REFILL_SYNC edge.
            // Wait one more BRAM read edge before checking the new valid/tag.
            REFILL_SYNC: begin
                next_state = TAG_CHECK;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(*) begin
        inst_valid = 1'b0;
        inst_out   = 32'd0;
        cpu_ren    = 4'b0000;
        cpu_raddr  = {req_addr[31:4], 4'b0000};

        if (!cpu_rst) begin
            if ((state == TAG_CHECK) && cache_hit) begin
                inst_valid = 1'b1;

                case (word_offset)
                    2'b00: inst_out = cache_line_r[31:0];
                    2'b01: inst_out = cache_line_r[63:32];
                    2'b10: inst_out = cache_line_r[95:64];
                    2'b11: inst_out = cache_line_r[127:96];
                    default: inst_out = 32'd0;
                endcase
            end

            // Hold valid and address until the bus-side ready handshake.
            if (state == REFILL_REQ) begin
                cpu_ren = 4'hf;
            end
        end
    end

    /******** 不要修改以下代码 ********/
`else

    localparam IDLE  = 2'b00;
    localparam STAT0 = 2'b01;
    localparam STAT1 = 2'b11;
    reg [1:0] state, nstat;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        state <= cpu_rst ? IDLE : nstat;
    end

    always @(*) begin
        case (state)
            IDLE:    nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0:   nstat = dev_rrdy ? STAT1 : STAT0;
            STAT1:   nstat = dev_rvalid ? IDLE : STAT1;
            default: nstat = IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            inst_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    cpu_ren    <= (inst_rreq & dev_rrdy) ? 4'hF : 4'h0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    cpu_ren    <= dev_rrdy ? 4'hF : 4'h0;
                end
                STAT1: begin
                    cpu_ren    <= 4'h0;
                    inst_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    inst_out   <= dev_rvalid ? dev_rdata[31:0] : 32'h0;
                end
                default: begin
                    inst_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end
            endcase
        end
    end

`endif

    // A request is accepted only while the cache is idle.  Exposing this
    // handshake prevents a redirect request from being lost while the cache
    // is still returning an older instruction.
    assign inst_ready = (state == IDLE);

endmodule

