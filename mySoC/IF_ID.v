`timescale 1ns / 1ps

module IF_ID (
    input  wire        clk,
    input  wire        rst,

    input  wire        stall,
    input  wire        flush,

    input  wire        if_valid,

    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,

    output reg  [31:0] id_pc,
    output reg  [31:0] id_inst
);


always @(posedge clk or posedge rst) begin

    if (rst) begin
        id_pc   <= 32'h0;
        id_inst <= 32'h00000013;   // NOP(addi x0,x0,0)
    end

    else if (flush) begin
        id_pc   <= 32'h0;
        id_inst <= 32'h00000013;
    end

    else if (stall) begin
        // stall时保持ID阶段内容
        id_pc   <= id_pc;
        id_inst <= id_inst;
    end

    else if (if_valid) begin
        id_pc   <= if_pc;
        id_inst <= if_inst;
    end

    else begin
        id_pc   <= 32'h0;
        id_inst <= 32'h00000013;
    end

end

endmodule

