// Forwarding.v
`timescale 1ns / 1ps
`include "defines.vh"

module Forwarding (
    // ID stage register read addresses
    input  wire [ 4:0]  id_rs1,
    input  wire [ 4:0]  id_rs2,
    // EX/MEM stage
    input  wire [ 4:0]  mem_rd,
    input  wire         mem_rf_we,
    // MEM/WB stage
    input  wire [ 4:0]  wb_rd,
    input  wire         wb_rf_we,
    // Forwarding control outputs
    output reg  [ 1:0]  forward_a,
    output reg  [ 1:0]  forward_b
);

    always @(*) begin
        // Default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;

        // Forwarding for operand A (rs1)
        if (mem_rf_we && (mem_rd != 5'h0) && (mem_rd == id_rs1)) begin
            forward_a = 2'b10;  // Forward from MEM stage
        end else if (wb_rf_we && (wb_rd != 5'h0) && (wb_rd == id_rs1)) begin
            forward_a = 2'b01;  // Forward from WB stage
        end

        // Forwarding for operand B (rs2)
        if (mem_rf_we && (mem_rd != 5'h0) && (mem_rd == id_rs2)) begin
            forward_b = 2'b10;  // Forward from MEM stage
        end else if (wb_rf_we && (wb_rd != 5'h0) && (wb_rd == id_rs2)) begin
            forward_b = 2'b01;  // Forward from WB stage
        end
    end

endmodule
