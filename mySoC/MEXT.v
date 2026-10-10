`timescale 1ns / 1ps
`include "defines.vh"

module MEXT (
    input  wire [ 2:0] op,
    input  wire [31:0] din,
    input  wire [ 1:0] byte_offs,
    output reg  [31:0] ext
);

    reg [31:0] shifted_din;

    // Move the addressed byte to bit 0. Halfword loads are only issued for
    // offsets 0 and 2 by MREQ, so the same shift also handles LH/LHU.
    always @(*) begin
        case (byte_offs)
            2'b01: shifted_din = { 8'h0, din[31:8]};
            2'b10: shifted_din = {16'h0, din[31:16]};
            2'b11: shifted_din = {24'h0, din[31:24]};
            default: shifted_din = din;
        endcase
    end

    always @(*) begin
        case (op)
            `RAM_EXT_B : ext = {{24{shifted_din[7]}}, shifted_din[7:0]};
            `RAM_EXT_BU: ext = {24'h0, shifted_din[7:0]};
            `RAM_EXT_H : ext = {{16{shifted_din[15]}}, shifted_din[15:0]};
            `RAM_EXT_HU: ext = {16'h0, shifted_din[15:0]};
            `RAM_EXT_W : ext = shifted_din;
            default    : ext = 32'h0;
        endcase
    end

endmodule

