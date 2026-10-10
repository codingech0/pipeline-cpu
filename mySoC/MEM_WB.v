// MEM_WB.v - �޸ĺ���������
`timescale 1ns / 1ps
`include "defines.vh"

module MEM_WB (
    input  wire         clk,
    input  wire         rst,
    input  wire         stall,
    input  wire         flush,
    // MEM stage inputs
    input  wire [31:0]  mem_alu_result,
    input  wire [31:0]  mem_load_data,
    input  wire [31:0]  mem_pc,
    input  wire [31:0]  mem_imm,         // �� ������������
    input  wire [ 4:0]  mem_rd,
    input  wire         mem_rf_we,
    input  wire [ 1:0]  mem_rf_wsel,
    input  wire         mem_is_mul_div,
    input  wire         mem_is_ld_st,
    // WB stage outputs
    output reg  [31:0]  wb_alu_result,
    output reg  [31:0]  wb_load_data,
    output reg  [31:0]  wb_pc,
    output reg  [31:0]  wb_imm,          // �� ������������
    output reg  [ 4:0]  wb_rd,
    output reg          wb_rf_we,
    output reg  [ 1:0]  wb_rf_wsel,
    output reg          wb_is_mul_div,
    output reg          wb_is_ld_st
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_alu_result <= 32'h0;
            wb_load_data  <= 32'h0;
            wb_pc         <= 32'h0;
            wb_imm        <= 32'h0;      // �� ����
            wb_rd         <= 5'h0;
            wb_rf_we      <= 1'b0;
            wb_rf_wsel    <= `WB_ALU;
            wb_is_mul_div <= 1'b0;
            wb_is_ld_st   <= 1'b0;
        end else if (flush) begin
            wb_alu_result <= 32'h0;
            wb_load_data  <= 32'h0;
            wb_pc         <= 32'h0;
            wb_imm        <= 32'h0;      // �� ����
            wb_rd         <= 5'h0;
            wb_rf_we      <= 1'b0;
            wb_rf_wsel    <= `WB_ALU;
            wb_is_mul_div <= 1'b0;
            wb_is_ld_st   <= 1'b0;
        end else if (!stall) begin
            wb_alu_result <= mem_alu_result;
            wb_load_data  <= mem_load_data;
            wb_pc         <= mem_pc;
            wb_imm        <= mem_imm;    // �� ����
            wb_rd         <= mem_rd;
            wb_rf_we      <= mem_rf_we;
            wb_rf_wsel    <= mem_rf_wsel;
            wb_is_mul_div <= mem_is_mul_div;
            wb_is_ld_st   <= mem_is_ld_st;
        end
    end

endmodule
