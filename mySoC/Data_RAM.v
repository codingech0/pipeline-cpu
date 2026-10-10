`timescale 1ns / 1ps

`include "defines.vh"

module Data_RAM (
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire [ 3:0]  data_ren,
    input  wire [31:0]  data_addr,
    output reg          data_valid,
    output wire [31:0]  data_rdata,
    input  wire [ 3:0]  data_wen,
    input  wire [31:0]  data_wdata,
    output reg          data_wresp
);

    reg [31:0] dram_wdata;

    // daccess_wdata always carries the complete register value. Align its low
    // byte or low halfword to the selected BRAM byte lanes only at this final
    // memory boundary.
    always @(*) begin
        case (data_wen)
            4'b0010: dram_wdata = data_wdata << 8;
            4'b0100: dram_wdata = data_wdata << 16;
            4'b1000: dram_wdata = data_wdata << 24;
            4'b1100: dram_wdata = data_wdata << 16;
            default: dram_wdata = data_wdata;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        data_valid <= cpu_rst ? 1'b0 : |data_ren;
        data_wresp <= cpu_rst ? 1'b0 : |data_wen;
    end

    DRAM U_dram (
        .clka   (cpu_clk),
        .addra  (data_addr[31:2]),
        .douta  (data_rdata),
        .wea    (data_wen),
        .dina   (dram_wdata)
    );

endmodule

