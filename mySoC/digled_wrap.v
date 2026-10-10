`timescale 1ns / 1ps

module digled_wrap (
    input wire aclk,
    input wire aresetn,

    input wire [31:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input  wire [ 7:0]  s_axi_awlen,
    input  wire [ 2:0]  s_axi_awsize,
    input  wire [ 1:0]  s_axi_awburst,
    input  wire [ 0:0]  s_axi_awlock,
    input  wire [ 3:0]  s_axi_awcache,
    input  wire [ 2:0]  s_axi_awprot,
    input  wire [ 3:0]  s_axi_awregion,
    input  wire [ 3:0]  s_axi_awqos,

    input wire [31:0] s_axi_wdata,
    input wire [3:0]  s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    input  wire         s_axi_wlast,

    output wire [1:0] s_axi_bresp,
    output reg  s_axi_bvalid,
    input wire s_axi_bready,

    input wire [31:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,

    output reg [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    input  wire [ 7:0]  s_axi_arlen,
    input  wire [ 2:0]  s_axi_arsize,
    input  wire [ 1:0]  s_axi_arburst,
    input  wire [ 0:0]  s_axi_arlock,
    input  wire [ 3:0]  s_axi_arcache,
    input  wire [ 2:0]  s_axi_arprot,
    input  wire [ 3:0]  s_axi_arregion,
    input  wire [ 3:0]  s_axi_arqos,
   
    output wire         s_axi_rlast,

    output reg [7:0] dig_en,
    output reg [7:0] dig_seg,
    output wire [7:0] dig_seg1
);

/******** AXI channel handshakes ********/
reg        aw_pending;
reg [31:0] saved_awaddr;
reg        w_pending;
reg [31:0] saved_wdata;
reg [ 3:0] saved_wstrb;

assign s_axi_awready = !aw_pending && !s_axi_bvalid;
assign s_axi_wready  = !w_pending  && !s_axi_bvalid;
assign s_axi_arready = !s_axi_rvalid;
assign s_axi_bresp = 2'b00;
assign s_axi_rresp = 2'b00;
assign s_axi_rlast = 1'b1;

wire aw_fire = s_axi_awvalid && s_axi_awready;
wire w_fire  = s_axi_wvalid  && s_axi_wready;
wire write_commit =
    !s_axi_bvalid && (aw_pending || aw_fire) && (w_pending || w_fire);
wire [31:0] commit_awaddr = aw_pending ? saved_awaddr : s_axi_awaddr;
wire [31:0] commit_wdata  = w_pending  ? saved_wdata  : s_axi_wdata;
wire [ 3:0] commit_wstrb  = w_pending  ? saved_wstrb  : s_axi_wstrb;

/******** Display register ********/
reg [31:0] display_data;

always @(posedge aclk) begin
    if (!aresetn) begin
        display_data  <= 32'h0000_0000;
        aw_pending    <= 1'b0;
        saved_awaddr  <= 32'h0000_0000;
        w_pending     <= 1'b0;
        saved_wdata   <= 32'h0000_0000;
        saved_wstrb   <= 4'h0;
        s_axi_bvalid  <= 1'b0;
    end else begin
        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;

        if (write_commit) begin
            if (commit_awaddr[3:0] == 4'h0) begin
                if (commit_wstrb[0])
                    display_data[7:0] <= commit_wdata[7:0];
                if (commit_wstrb[1])
                    display_data[15:8] <= commit_wdata[15:8];
                if (commit_wstrb[2])
                    display_data[23:16] <= commit_wdata[23:16];
                if (commit_wstrb[3])
                    display_data[31:24] <= commit_wdata[31:24];
            end
            aw_pending   <= 1'b0;
            w_pending    <= 1'b0;
            s_axi_bvalid <= 1'b1;
        end else begin
            if (aw_fire) begin
                aw_pending   <= 1'b1;
                saved_awaddr <= s_axi_awaddr;
            end
            if (w_fire) begin
                w_pending   <= 1'b1;
                saved_wdata <= s_axi_wdata;
                saved_wstrb <= s_axi_wstrb;
            end
        end
    end
end

/******** AXI read ********/
always @(posedge aclk) begin
    if (!aresetn) begin
        s_axi_rvalid <= 1'b0;
        s_axi_rdata  <= 32'h0000_0000;
    end else begin
        if (s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 1'b0;

        if (s_axi_arvalid && s_axi_arready) begin
            if (s_axi_araddr[3:0] == 0)
                s_axi_rdata <= display_data;
            else
                s_axi_rdata <= 0;
            s_axi_rvalid <= 1'b1;
        end
    end
end

/******** Eight-digit scan ********/
reg [15:0] clk_div;
reg [2:0] scan_cnt;

always @(posedge aclk) begin
    if (!aresetn) begin
        clk_div <= 0;
        scan_cnt <= 0;
    end else begin
        if (clk_div == 16'd50000) begin
            clk_div <= 0;
            scan_cnt <= scan_cnt + 1'b1;
        end else begin
            clk_div <= clk_div + 1'b1;
        end
    end
end

/******** Select the current hexadecimal nibble ********/
reg [3:0] hex_data;

always @(*) begin
    case (scan_cnt)
        3'd0: hex_data = display_data[3:0];
        3'd1: hex_data = display_data[7:4];
        3'd2: hex_data = display_data[11:8];
        3'd3: hex_data = display_data[15:12];
        3'd4: hex_data = display_data[19:16];
        3'd5: hex_data = display_data[23:20];
        3'd6: hex_data = display_data[27:24];
        3'd7: hex_data = display_data[31:28];
    endcase
end

/******** EGO1 common-cathode segment table (active high) ********/
reg [7:0] seg;

always @(*) begin
    case (hex_data)
        // Port order: {CA, CB, CC, CD, CE, CF, CG, DP}.
        4'h0: seg = 8'b11111100;
        4'h1: seg = 8'b01100000;
        4'h2: seg = 8'b11011010;
        4'h3: seg = 8'b11110010;
        4'h4: seg = 8'b01100110;
        4'h5: seg = 8'b10110110;
        4'h6: seg = 8'b10111110;
        4'h7: seg = 8'b11100000;
        4'h8: seg = 8'b11111110;
        4'h9: seg = 8'b11110110;
        4'ha: seg = 8'b11101110;
        4'hb: seg = 8'b00111110;
        4'hc: seg = 8'b10011100;
        4'hd: seg = 8'b01111010;
        4'he: seg = 8'b10011110;
        4'hf: seg = 8'b10001110;
        default: seg = 8'b00000000;
    endcase

    dig_seg = seg;
end

/******** EGO1 digit select (active high) ********/
always @(*) begin
    dig_en = 8'b00000000;
    case (scan_cnt)
        3'd0: dig_en = 8'b00000001;
        3'd1: dig_en = 8'b00000010;
        3'd2: dig_en = 8'b00000100;
        3'd3: dig_en = 8'b00001000;
        3'd4: dig_en = 8'b00010000;
        3'd5: dig_en = 8'b00100000;
        3'd6: dig_en = 8'b01000000;
        3'd7: dig_en = 8'b10000000;
    endcase
end

// EGO1 has two four-digit banks with separate but identical segment buses.
assign dig_seg1 = dig_seg;

endmodule

