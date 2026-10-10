`timescale 1ns / 1ps

module PC (
    input  wire         clk,
    input  wire         rst,
    input  wire         en,
    input  wire [31:0]  npc,
    input  wire         fetch,
    output reg  [31:0]  pc
);

    always @(posedge clk or posedge rst) begin
        if (rst)
          pc <= 32'h0;
        else  if (en)
          pc <= npc;
    end
    
endmodule

