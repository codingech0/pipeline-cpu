`timescale 1ns / 1ps
`include "defines.vh"

module MREQ (
    input  wire [31:0] ram_addr,

    input  wire [ 2:0] ram_rop,
    output reg  [ 3:0] da_ren,
    output wire [31:0] da_addr,

    input  wire [ 3:0] ram_wop,
    input  wire [31:0] ram_wdata,
    output reg  [ 3:0] da_wen,
    output reg  [31:0] da_wdata
);

    wire [1:0] offset = ram_addr[1:0];

    // The block RAM discards address bits [1:0]; they select its byte lanes.
    assign da_addr = ram_addr;

    always @(*) begin
        da_wen   = 4'b0000;
        // Keep the complete source-register value on the data bus. The byte
        // enable selects the bytes to update; Data_RAM performs lane alignment.
        da_wdata = ram_wdata;

        case (ram_wop)
            `RAM_WE_B: begin
                case (offset)
                    2'b00: da_wen = 4'b0001;
                    2'b01: da_wen = 4'b0010;
                    2'b10: da_wen = 4'b0100;
                    2'b11: da_wen = 4'b1000;
                endcase
            end

            `RAM_WE_H: begin
                // RISC-V halfword accesses must be 2-byte aligned.
                if (offset == 2'b00) begin
                    da_wen = 4'b0011;
                end else if (offset == 2'b10) begin
                    da_wen = 4'b1100;
                end
            end

            `RAM_WE_W: begin
                // RISC-V word accesses must be 4-byte aligned.
                if (offset == 2'b00) begin
                    da_wen = 4'b1111;
                end
            end

            default: begin
                da_wen = 4'b0000;
            end
        endcase
    end

    always @(*) begin
        da_ren = 4'b0000;

        case (ram_rop)
            `RAM_EXT_B,
            `RAM_EXT_BU: da_ren = 4'b0001 << offset;

            `RAM_EXT_H,
            `RAM_EXT_HU: begin
                if (offset == 2'b00)
                    da_ren = 4'b0011;
                else if (offset == 2'b10)
                    da_ren = 4'b1100;
            end

            `RAM_EXT_W: begin
                if (offset == 2'b00)
                    da_ren = 4'b1111;
            end

            default: da_ren = 4'b0000;
        endcase
    end

endmodule

