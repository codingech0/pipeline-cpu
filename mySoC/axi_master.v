`timescale 1ns / 1ps

// Standalone defaults for this repository. Definitions from the course
// configuration header take precedence when they already exist.
`ifndef IC_BLK_SIZE
`define IC_BLK_SIZE 128
`endif

`ifndef DC_BLK_SIZE
`define DC_BLK_SIZE 128
`endif

module axi_master(
    input  wire         aclk,
    input  wire         areset,     // high active

    // ICache Interface
    output reg          ic_dev_rrdy,
    input  wire [ 3:0]  ic_cpu_ren,
    input  wire [31:0]  ic_cpu_raddr,
    output reg          ic_dev_rvalid,
    output reg  [`IC_BLK_SIZE-1:0]  ic_dev_rdata,
    // DCache Interface
    output reg          dc_dev_wrdy,
    input  wire [ 3:0]  dc_cpu_wen,
    input  wire [31:0]  dc_cpu_waddr,
    input  wire [31:0]  dc_cpu_wdata,
    output reg          dc_dev_rrdy,
    input  wire [ 3:0]  dc_cpu_ren,
    input  wire [31:0]  dc_cpu_raddr,
    output reg          dc_dev_rvalid,
    output reg  [`DC_BLK_SIZE-1:0]  dc_dev_rdata,

    // AXI4 Master Interface
    // write address channel
    output reg  [31:0]  m_axi_awaddr,
    output reg  [ 7:0]  m_axi_awlen,
    output reg  [ 2:0]  m_axi_awsize,
    output reg  [ 1:0]  m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    // write data channel
    output reg  [31:0]  m_axi_wdata,
    output reg  [ 3:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    // write response channel
    output reg          m_axi_bready,
    input  wire [ 1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    // read address channel
    output reg  [31:0]  m_axi_araddr,
    output reg  [ 7:0]  m_axi_arlen,
    output reg  [ 2:0]  m_axi_arsize,
    output reg  [ 1:0]  m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    // read data channel
    output reg          m_axi_rready,
    input  wire [31:0]  m_axi_rdata,
    input  wire [ 1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid
);

    localparam integer IC_READ_BEATS = `IC_BLK_SIZE / 32;
    localparam integer DC_READ_BEATS = `DC_BLK_SIZE / 32;
    localparam integer MAX_READ_BEATS =
        (IC_READ_BEATS > DC_READ_BEATS) ? IC_READ_BEATS : DC_READ_BEATS;
    localparam [7:0] IC_ARLEN = IC_READ_BEATS - 1;
    localparam [7:0] DC_ARLEN = DC_READ_BEATS - 1;

    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_READ_ADDR   = 4'd1;
    localparam [3:0] ST_READ_DATA   = 4'd2;
    localparam [3:0] ST_READ_RETURN = 4'd3;
    localparam [3:0] ST_WRITE_BOTH  = 4'd4;
    localparam [3:0] ST_WRITE_ADDR  = 4'd5;
    localparam [3:0] ST_WRITE_DATA  = 4'd6;
    localparam [3:0] ST_WRITE_RESP  = 4'd7;

    localparam READ_OWNER_ICACHE = 1'b0;
    localparam READ_OWNER_DCACHE = 1'b1;

    reg [3:0] state;
    reg [3:0] next_state;

    reg        read_owner;
    reg [31:0] read_addr_reg;
    integer    read_beat_count;
    reg [31:0] read_words [0:MAX_READ_BEATS-1];

    reg [31:0] write_addr_reg;
    reg [31:0] write_data_reg;
    reg [ 3:0] write_strb_reg;

    integer reset_word_index;
    integer pack_word_index;

    wire read_data_handshake;
    wire write_response_handshake;
    wire read_is_uncached;
    wire unused_response;

    assign m_axi_wlast = 1'b1;

    assign read_data_handshake =
        m_axi_rvalid && m_axi_rready;
    assign write_response_handshake =
        m_axi_bvalid && m_axi_bready;
    assign read_is_uncached =
        (read_owner == READ_OWNER_DCACHE) &&
        (read_addr_reg[31:16] == 16'hffff);

    // Responses are ignored in this lab. The AXI slave is expected to return
    // OKAY; referencing the signals here prevents unused-input warnings.
    assign unused_response = &{1'b0, m_axi_bresp, m_axi_rresp};

    // AXI outputs, Cache ready signals, and one-cycle Cache read response.
    always @(*) begin
        ic_dev_rrdy   = 1'b0;
        ic_dev_rvalid = 1'b0;
        ic_dev_rdata  = {`IC_BLK_SIZE{1'b0}};

        dc_dev_wrdy   = 1'b0;
        dc_dev_rrdy   = 1'b0;
        dc_dev_rvalid = 1'b0;
        dc_dev_rdata  = {`DC_BLK_SIZE{1'b0}};

        for (
            pack_word_index = 0;
            pack_word_index < IC_READ_BEATS;
            pack_word_index = pack_word_index + 1
        ) begin
            ic_dev_rdata[
                pack_word_index * 32 +: 32
            ] = read_words[pack_word_index];
        end

        for (
            pack_word_index = 0;
            pack_word_index < DC_READ_BEATS;
            pack_word_index = pack_word_index + 1
        ) begin
            dc_dev_rdata[
                pack_word_index * 32 +: 32
            ] = read_words[pack_word_index];
        end

        m_axi_awaddr  = write_addr_reg;
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = 3'd2;
        m_axi_awburst = 2'b01;
        m_axi_awvalid = 1'b0;

        m_axi_wdata   = write_data_reg;
        m_axi_wstrb   = write_strb_reg;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;

        m_axi_araddr  = read_addr_reg;
        m_axi_arlen   =
            read_is_uncached ? 8'd0 :
            ((read_owner == READ_OWNER_DCACHE) ?
            DC_ARLEN : IC_ARLEN);
        m_axi_arsize  = 3'd2;
        m_axi_arburst = 2'b01;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        if (!areset) begin
            m_axi_bready = 1'b1;
            m_axi_rready = 1'b1;

            case (state)
                ST_IDLE: begin
                    // DCache write > DCache read > ICache read.
                    dc_dev_wrdy = 1'b1;

                    if (dc_cpu_wen == 4'b0000) begin
                        dc_dev_rrdy = 1'b1;

                        if (!(|dc_cpu_ren)) begin
                            ic_dev_rrdy = 1'b1;
                        end
                    end
                end

                ST_READ_ADDR: begin
                    m_axi_arvalid = 1'b1;
                end

                ST_READ_RETURN: begin
                    if (read_owner == READ_OWNER_DCACHE) begin
                        dc_dev_rvalid = 1'b1;
                    end
                    else begin
                        ic_dev_rvalid = 1'b1;
                    end
                end

                ST_WRITE_BOTH: begin
                    m_axi_awvalid = 1'b1;
                    m_axi_wvalid  = 1'b1;
                end

                ST_WRITE_ADDR: begin
                    m_axi_awvalid = 1'b1;
                end

                ST_WRITE_DATA: begin
                    m_axi_wvalid = 1'b1;
                end

                default: begin
                end
            endcase
        end
    end

    // Next-state logic.
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (dc_cpu_wen != 4'b0000) begin
                    next_state = ST_WRITE_BOTH;
                end
                else if (|dc_cpu_ren) begin
                    next_state = ST_READ_ADDR;
                end
                else if (|ic_cpu_ren) begin
                    next_state = ST_READ_ADDR;
                end
            end

            ST_READ_ADDR: begin
                if (m_axi_arready) begin
                    next_state = ST_READ_DATA;
                end
            end

            ST_READ_DATA: begin
                if (read_data_handshake && m_axi_rlast) begin
                    next_state = ST_READ_RETURN;
                end
            end

            ST_READ_RETURN: begin
                next_state = ST_IDLE;
            end

            ST_WRITE_BOTH: begin
                case ({m_axi_awready, m_axi_wready})
                    2'b11:   next_state = ST_WRITE_RESP;
                    2'b10:   next_state = ST_WRITE_DATA;
                    2'b01:   next_state = ST_WRITE_ADDR;
                    default: next_state = ST_WRITE_BOTH;
                endcase
            end

            ST_WRITE_ADDR: begin
                if (m_axi_awready) begin
                    next_state = ST_WRITE_RESP;
                end
            end

            ST_WRITE_DATA: begin
                if (m_axi_wready) begin
                    next_state = ST_WRITE_RESP;
                end
            end

            ST_WRITE_RESP: begin
                if (write_response_handshake) begin
                    next_state = ST_IDLE;
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // State and payload registers.
    always @(posedge aclk) begin
        if (areset) begin
            state            <= ST_IDLE;
            read_owner       <= READ_OWNER_ICACHE;
            read_addr_reg    <= 32'd0;
            read_beat_count  <= 0;
            write_addr_reg   <= 32'd0;
            write_data_reg   <= 32'd0;
            write_strb_reg   <= 4'd0;

            for (
                reset_word_index = 0;
                reset_word_index < MAX_READ_BEATS;
                reset_word_index = reset_word_index + 1
            ) begin
                read_words[reset_word_index] <= 32'd0;
            end
        end
        else begin
            state <= next_state;

            if (state == ST_IDLE) begin
                if (dc_cpu_wen != 4'b0000) begin
                    write_addr_reg <= dc_cpu_waddr;
                    write_data_reg <= dc_cpu_wdata;
                    write_strb_reg <= dc_cpu_wen;
                end
                else if (|dc_cpu_ren) begin
                    read_owner      <= READ_OWNER_DCACHE;
                    read_addr_reg   <= dc_cpu_raddr;
                    read_beat_count <= 0;

                    for (
                        reset_word_index = 0;
                        reset_word_index < MAX_READ_BEATS;
                        reset_word_index = reset_word_index + 1
                    ) begin
                        read_words[reset_word_index] <= 32'd0;
                    end
                end
                else if (|ic_cpu_ren) begin
                    read_owner      <= READ_OWNER_ICACHE;
                    read_addr_reg   <= ic_cpu_raddr;
                    read_beat_count <= 0;

                    for (
                        reset_word_index = 0;
                        reset_word_index < MAX_READ_BEATS;
                        reset_word_index = reset_word_index + 1
                    ) begin
                        read_words[reset_word_index] <= 32'd0;
                    end
                end
            end

            if ((state == ST_READ_DATA) && read_data_handshake) begin
                read_words[read_beat_count] <= m_axi_rdata;

                if (m_axi_rlast) begin
                    read_beat_count <= 0;
                end
                else begin
                    read_beat_count <= read_beat_count + 1;
                end
            end
        end
    end

endmodule

