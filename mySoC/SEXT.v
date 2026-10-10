// SEXT.v (�޸İ�)
`timescale 1ns / 1ps
`include "defines.vh"

module SEXT (
    input  wire [ 2:0]  op,
    input  wire [31:7]  imm,
    output reg  [31:0]  imm_ext
);

    always @(*) begin
        case (op)
            `EXT_I : imm_ext = {{20{imm[31]}}, imm[31:20]};
            `EXT_S : imm_ext = {{20{imm[31]}}, imm[31:25], imm[11:7]};
            `EXT_B : imm_ext = {{19{imm[31]}}, imm[31], imm[7], imm[30:25], imm[11:8], 1'b0};
            `EXT_U : imm_ext = {imm[31:12], 12'h0};
            `EXT_J : imm_ext = {{11{imm[31]}}, imm[31], imm[19:12], imm[20], imm[30:21], 1'b0};
            default: imm_ext = 32'h0;
        endcase
    end
    
endmodule
