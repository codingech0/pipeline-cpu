// EX_MEM.v - 修改后完整代码
`timescale 1ns / 1ps
`include "defines.vh"

module EX_MEM (
    input  wire         clk,
    input  wire         rst,
    input  wire         stall,
    input  wire         flush,
    // EX stage inputs
    input  wire [31:0]  ex_alu_result,
    input  wire [31:0]  ex_rs2_data,
    input  wire [31:0]  ex_pc,
    input  wire [31:0]  ex_imm,          // ← 新增：立即数
    input  wire [ 4:0]  ex_rd,
    input  wire [ 2:0]  ex_ram_rop,
    input  wire [ 3:0]  ex_ram_wop,
    input  wire         ex_rf_we,
    input  wire [ 1:0]  ex_rf_wsel,
    input  wire         ex_is_mul_div,
    input  wire         ex_is_ld_st,
    // MEM stage outputs
    output reg  [31:0]  mem_alu_result,
    output reg  [31:0]  mem_rs2_data,
    output reg  [31:0]  mem_pc,
    output reg  [31:0]  mem_imm,         // ← 新增：立即数
    output reg  [ 4:0]  mem_rd,
    output reg  [ 2:0]  mem_ram_rop,
    output reg  [ 3:0]  mem_ram_wop,
    output reg          mem_rf_we,
    output reg  [ 1:0]  mem_rf_wsel,
    output reg          mem_is_mul_div,
    output reg          mem_is_ld_st
    // ← 删除 mem_br_taken
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_alu_result <= 32'h0;
            mem_rs2_data   <= 32'h0;
            mem_pc         <= 32'h0;
            mem_imm        <= 32'h0;     // ← 新增
            mem_rd         <= 5'h0;
            mem_ram_rop    <= `RAM_EXT_N;
            mem_ram_wop    <= `RAM_WE_N;
            mem_rf_we      <= 1'b0;
            mem_rf_wsel    <= `WB_ALU;
            mem_is_mul_div <= 1'b0;
            mem_is_ld_st   <= 1'b0;
        end else if (stall) begin
            // Hold the EX/MEM register while an older memory request waits.
        end else if (flush) begin
            mem_alu_result <= 32'h0;
            mem_rs2_data   <= 32'h0;
            mem_pc         <= 32'h0;
            mem_imm        <= 32'h0;     // ← 新增
            mem_rd         <= 5'h0;
            mem_ram_rop    <= `RAM_EXT_N;
            mem_ram_wop    <= `RAM_WE_N;
            mem_rf_we      <= 1'b0;
            mem_rf_wsel    <= `WB_ALU;
            mem_is_mul_div <= 1'b0;
            mem_is_ld_st   <= 1'b0;
        end else begin
            mem_alu_result <= ex_alu_result;
            mem_rs2_data   <= ex_rs2_data;
            mem_pc         <= ex_pc;
            mem_imm        <= ex_imm;    // ← 新增
            mem_rd         <= ex_rd;
            mem_ram_rop    <= ex_ram_rop;
            mem_ram_wop    <= ex_ram_wop;
            mem_rf_we      <= ex_rf_we;
            mem_rf_wsel    <= ex_rf_wsel;
            mem_is_mul_div <= ex_is_mul_div;
            mem_is_ld_st   <= ex_is_ld_st;
        end
    end

endmodule

