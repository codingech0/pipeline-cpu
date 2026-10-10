// ID_EX.v
`timescale 1ns / 1ps
`include "defines.vh"

module ID_EX (
    input  wire         clk,
    input  wire         rst,
    input  wire         stall,
    input  wire         flush,
    // ID stage inputs
    input  wire [31:0]  id_pc,
    input  wire [31:0]  id_rs1_data,
    input  wire [31:0]  id_rs2_data,
    input  wire [31:0]  id_imm,
    input  wire [ 4:0]  id_rs1,
    input  wire [ 4:0]  id_rs2,
    input  wire [ 4:0]  id_rd,
    input  wire [ 4:0]  id_alu_op,
    input  wire         id_alua_sel,
    input  wire         id_alub_sel,
    input  wire [ 2:0]  id_ram_rop,
    input  wire [ 3:0]  id_ram_wop,
    input  wire         id_rf_we,
    input  wire [ 1:0]  id_rf_wsel,
    input  wire         id_is_mul_div,
    input  wire         id_is_ld_st,
    input  wire [ 1:0]  id_npc_op,
    // EX stage outputs
    output reg  [31:0]  ex_pc,
    output reg  [31:0]  ex_rs1_data,
    output reg  [31:0]  ex_rs2_data,
    output reg  [31:0]  ex_imm,
    output reg  [ 4:0]  ex_rs1,
    output reg  [ 4:0]  ex_rs2,
    output reg  [ 4:0]  ex_rd,
    output reg  [ 4:0]  ex_alu_op,
    output reg          ex_alua_sel,
    output reg          ex_alub_sel,
    output reg  [ 2:0]  ex_ram_rop,
    output reg  [ 3:0]  ex_ram_wop,
    output reg          ex_rf_we,
    output reg  [ 1:0]  ex_rf_wsel,
    output reg          ex_is_mul_div,
    output reg          ex_is_ld_st,
    output reg  [ 1:0]  ex_npc_op
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_pc        <= 32'h0;
            ex_rs1_data  <= 32'h0;
            ex_rs2_data  <= 32'h0;
            ex_imm       <= 32'h0;
            ex_rs1       <= 5'h0;
            ex_rs2       <= 5'h0;
            ex_rd        <= 5'h0;
            ex_alu_op    <= `ALU_ADD;
            ex_alua_sel  <= 1'b0;
            ex_alub_sel  <= 1'b0;
            ex_ram_rop   <= `RAM_EXT_N;
            ex_ram_wop   <= `RAM_WE_N;
            ex_rf_we     <= 1'b0;
            ex_rf_wsel   <= `WB_ALU;
            ex_is_mul_div <= 1'b0;
            ex_is_ld_st  <= 1'b0;
            ex_npc_op    <= `NPC_PC4;
        end else if (flush) begin
            ex_pc        <= 32'h0;
            ex_rs1_data  <= 32'h0;
            ex_rs2_data  <= 32'h0;
            ex_imm       <= 32'h0;
            ex_rs1       <= 5'h0;
            ex_rs2       <= 5'h0;
            ex_rd        <= 5'h0;
            ex_alu_op    <= `ALU_ADD;
            ex_alua_sel  <= 1'b0;
            ex_alub_sel  <= 1'b0;
            ex_ram_rop   <= `RAM_EXT_N;
            ex_ram_wop   <= `RAM_WE_N;
            ex_rf_we     <= 1'b0;
            ex_rf_wsel   <= `WB_ALU;
            ex_is_mul_div <= 1'b0;
            ex_is_ld_st  <= 1'b0;
            ex_npc_op    <= `NPC_PC4;
        end else if (!stall) begin
            ex_pc        <= id_pc;
            ex_rs1_data  <= id_rs1_data;
            ex_rs2_data  <= id_rs2_data;
            ex_imm       <= id_imm;
            ex_rs1       <= id_rs1;
            ex_rs2       <= id_rs2;
            ex_rd        <= id_rd;
            ex_alu_op    <= id_alu_op;
            ex_alua_sel  <= id_alua_sel;
            ex_alub_sel  <= id_alub_sel;
            ex_ram_rop   <= id_ram_rop;
            ex_ram_wop   <= id_ram_wop;
            ex_rf_we     <= id_rf_we;
            ex_rf_wsel   <= id_rf_wsel;
            ex_is_mul_div <= id_is_mul_div;
            ex_is_ld_st  <= id_is_ld_st;
            ex_npc_op    <= id_npc_op;
        end
    end

endmodule
