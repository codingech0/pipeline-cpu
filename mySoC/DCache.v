`timescale 1ns / 1ps

`include "defines.vh"

// �����ַλ����32bit
// Cache������1KB
// Cache���С��128bit (4*32bit)
// Cache�������64

module DCache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active 
    // Interface to CPU
    input  wire [ 3:0]  data_ren,       // ����CPU�Ķ�ʹ���ź�
    input  wire [31:0]  data_addr,      // ����CPU�ĵ�ַ������д���ã�
    output reg          data_valid,     // �����CPU��������Ч�ź�
    output reg  [31:0]  data_rdata,     // �����CPU�Ķ�����
    input  wire [ 3:0]  data_wen,       // ����CPU��дʹ���ź�
    input  wire [31:0]  data_wdata,     // ����CPU��д����
    output reg          data_wresp,     // �����CPU��д��Ӧ
    // Interface to Write Bus
    input  wire         dev_wrdy,       // ����/�����д�����ź�
    output reg  [ 3:0]  cpu_wen,        // ���������/�����дʹ���ź�
    output reg  [31:0]  cpu_waddr,      // ���������/�����д��ַ
    output reg  [31:0]  cpu_wdata,      // ���������/�����д����
    // Interface to Read Bus
    input  wire         dev_rrdy,       // ����/����Ķ������ź�
    output reg  [ 3:0]  cpu_ren,        // ���������/����Ķ�ʹ���ź�
    output reg  [31:0]  cpu_raddr,      // ���������/����Ķ���ַ
    input  wire         dev_rvalid,     // ��������/�����������Ч�ź�
    input  wire [127:0] dev_rdata       // ��������/����Ķ�����
);

    wire request_uncached =
        (data_addr[31:16] == 16'hffff);

    // MREQ keeps the complete rs2 value on data_wdata. The final memory
    // boundary must move its low byte/halfword into the byte lanes selected
    // by data_wen. Use the aligned value for both Cache merging and AXI WDATA.
    reg [31:0] aligned_data_wdata;
    always @(*) begin
        case (data_wen)
            4'b0010: aligned_data_wdata = data_wdata << 8;
            4'b0100: aligned_data_wdata = data_wdata << 16;
            4'b1000: aligned_data_wdata = data_wdata << 24;
            4'b1100: aligned_data_wdata = data_wdata << 16;
            default: aligned_data_wdata = data_wdata;
        endcase
    end

`ifdef ENABLE_DCACHE    /******** ��Ҫ�޸Ĵ��д��� ********/

    localparam [3:0] IDLE         = 4'd0;
    localparam [3:0] LOOKUP_WAIT  = 4'd1;
    localparam [3:0] READ_TAG     = 4'd2;
    localparam [3:0] READ_REQ     = 4'd3;
    localparam [3:0] READ_WAIT    = 4'd4;
    localparam [3:0] REFILL_SYNC  = 4'd5;
    localparam [3:0] WRITE_TAG    = 4'd6;
    localparam [3:0] WRITE_REQ    = 4'd7;
    localparam [3:0] WRITE_WAIT   = 4'd8;
    localparam [3:0] READ_DRAIN   = 4'd9;
    localparam [3:0] WRITE_DRAIN  = 4'd10;

    reg [3:0] state;
    reg [3:0] next_state;

    reg        req_is_write;
    reg        req_uncached;
    reg [31:0] req_addr;
    reg [ 3:0] req_wen;
    reg [31:0] req_wdata;

    wire [4:0] req_tag     = req_addr[14:10];
    wire [1:0] word_offset = req_addr[3:2];
    wire [5:0] cache_index = req_addr[9:4];

    wire [133:0] bram_rdata;
    wire         cache_valid = bram_rdata[133];
    wire [4:0]   cache_tag   = bram_rdata[132:128];
    wire         cache_hit   =
        (cache_valid === 1'b1) && (cache_tag == req_tag);

    wire [31:0] old_word =
        (word_offset == 2'b00) ? bram_rdata[31:0] :
        (word_offset == 2'b01) ? bram_rdata[63:32] :
        (word_offset == 2'b10) ? bram_rdata[95:64] :
                                 bram_rdata[127:96];

    wire [31:0] merged_word;
    assign merged_word[7:0] =
        req_wen[0] ? req_wdata[7:0] : old_word[7:0];
    assign merged_word[15:8] =
        req_wen[1] ? req_wdata[15:8] : old_word[15:8];
    assign merged_word[23:16] =
        req_wen[2] ? req_wdata[23:16] : old_word[23:16];
    assign merged_word[31:24] =
        req_wen[3] ? req_wdata[31:24] : old_word[31:24];

    reg [127:0] merged_block;
    always @(*) begin
        merged_block = bram_rdata[127:0];

        case (word_offset)
            2'b00: merged_block[31:0]   = merged_word;
            2'b01: merged_block[63:32]  = merged_word;
            2'b10: merged_block[95:64]  = merged_word;
            2'b11: merged_block[127:96] = merged_word;
            default: merged_block = bram_rdata[127:0];
        endcase
    end

    wire refill_we =
        (state == READ_WAIT) && dev_rvalid && !req_uncached;
    wire write_hit_we =
        (state == WRITE_TAG) && cache_hit && !req_uncached;
    wire bram_we = refill_we || write_hit_we;
    wire [133:0] bram_wdata =
        write_hit_we ?
        {1'b1, req_tag, merged_block} :
        {1'b1, req_tag, dev_rdata};

    blk_mem_gen_1 U_dsram (
        .clka   (cpu_clk),
        .wea    (bram_we),
        .addra  (cache_index),
        .dina   (bram_wdata),
        .douta  (bram_rdata)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            state         <= IDLE;
            req_is_write  <= 1'b0;
            req_uncached  <= 1'b0;
            req_addr      <= 32'd0;
            req_wen       <= 4'd0;
            req_wdata     <= 32'd0;
        end
        else begin
            state <= next_state;

            if (state == IDLE) begin
                if (|data_wen) begin
                    req_is_write <= 1'b1;
                    req_uncached <= request_uncached;
                    req_addr     <= data_addr;
                    req_wen      <= data_wen;
                    req_wdata    <= aligned_data_wdata;
                end
                else if (|data_ren) begin
                    req_is_write <= 1'b0;
                    req_uncached <= request_uncached;
                    req_addr     <= data_addr;
                    req_wen      <= 4'd0;
                    req_wdata    <= 32'd0;
                end
            end
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (|data_wen) begin
                    next_state =
                        request_uncached ? WRITE_REQ : LOOKUP_WAIT;
                end
                else if (|data_ren) begin
                    next_state =
                        request_uncached ? READ_REQ : LOOKUP_WAIT;
                end
            end

            // req_addr changes after the IDLE edge. Give synchronous BRAM one
            // complete read edge before evaluating its output.
            LOOKUP_WAIT: begin
                next_state = req_is_write ? WRITE_TAG : READ_TAG;
            end

            READ_TAG: begin
                next_state = cache_hit ? READ_DRAIN : READ_REQ;
            end

            READ_REQ: begin
                if (dev_rrdy) begin
                    next_state = READ_WAIT;
                end
            end

            READ_WAIT: begin
                if (dev_rvalid) begin
                    next_state =
                        req_uncached ? READ_DRAIN : REFILL_SYNC;
                end
            end

            // The refill was written on the previous edge. This state waits
            // for a clean synchronous read of the newly written line.
            REFILL_SYNC: begin
                next_state = READ_TAG;
            end

            // Write-through, no-write-allocate: update the line only on a hit,
            // then always forward the original store to the bus.
            WRITE_TAG: begin
                next_state = WRITE_REQ;
            end

            WRITE_REQ: begin
                if (dev_wrdy) begin
                    next_state = WRITE_WAIT;
                end
            end

            // dev_wrdy falls while axi_master is processing the accepted
            // request and rises again when the B response has completed.
            WRITE_WAIT: begin
                if (dev_wrdy) begin
                    next_state = WRITE_DRAIN;
                end
            end

            // cpu_core registers daccess_ren/daccess_wen. They remain asserted
            // for an extra cycle after the response is observed. Do not return
            // to IDLE until the old request level has been removed, otherwise
            // the same address can be accepted and answered a second time.
            READ_DRAIN: begin
                if (data_ren == 4'b0000) begin
                    next_state = IDLE;
                end
            end

            WRITE_DRAIN: begin
                if (data_wen == 4'b0000) begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(*) begin
        data_valid = 1'b0;
        data_rdata = 32'd0;
        data_wresp = 1'b0;

        cpu_wen   = 4'b0000;
        cpu_waddr = req_addr;
        cpu_wdata = req_wdata;

        cpu_ren   = 4'b0000;
        cpu_raddr =
            req_uncached ? req_addr : {req_addr[31:4], 4'b0000};

        if (!cpu_rst) begin
            case (state)
                READ_TAG: begin
                    if (cache_hit) begin
                        data_valid = 1'b1;

                        case (word_offset)
                            2'b00: data_rdata = bram_rdata[31:0];
                            2'b01: data_rdata = bram_rdata[63:32];
                            2'b10: data_rdata = bram_rdata[95:64];
                            2'b11: data_rdata = bram_rdata[127:96];
                            default: data_rdata = 32'd0;
                        endcase
                    end
                end

                READ_REQ: begin
                    // The bus controller read-enable input is scalar. Driving
                    // all bits avoids losing byte/half-word reads to truncation.
                    cpu_ren = 4'hf;
                end

                READ_WAIT: begin
                    if (req_uncached && dev_rvalid) begin
                        data_valid = 1'b1;
                        data_rdata = dev_rdata[31:0];
                    end
                end

                WRITE_REQ: begin
                    cpu_wen = req_wen;
                end

                WRITE_WAIT: begin
                    if (dev_wrdy) begin
                        data_wresp = 1'b1;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    /******** ��Ҫ�޸����´��� ********/
`else

    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_DRAIN = 2'b10;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        r_state <= cpu_rst ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_DRAIN : R_STAT1;
            R_DRAIN: r_nstat = (data_ren == 4'b0000) ? R_IDLE : R_DRAIN;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_valid <= 1'b0;
            data_rdata <= 32'h0;
            cpu_ren    <= 4'h0;
            cpu_raddr  <= 32'h0;
            ren_r      <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            cpu_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        cpu_raddr <= data_addr;
                    end else
                        cpu_ren   <= 4'h0;
                end
                R_STAT0: begin
                    cpu_ren    <= dev_rrdy ? ren_r : 4'h0;
                end
                R_STAT1: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                R_DRAIN: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= 1'b0;
                end
                default: begin
                    data_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_DRAIN = 2'b10;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (cpu_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        w_state <= cpu_rst ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_DRAIN : W_STAT1;
            W_DRAIN: w_nstat = (data_wen == 4'b0000) ? W_IDLE : W_DRAIN;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
            cpu_waddr  <= 32'h0;
            cpu_wdata  <= 32'h0;
            wen_r      <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;

                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= aligned_data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_STAT0: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                W_DRAIN: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule

