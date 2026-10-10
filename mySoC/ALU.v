`timescale 1ns / 1ps
`include "defines.vh"

module ALU (
    input  wire        rst,
    input  wire        clk,
    input  wire [ 4:0] op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] c,
    output reg         br,
    output wire        busy
);

    wire mul_start;
    wire mulhu_start;
    wire div_start;
    wire divu_start;

    wire        mul_busy;
    wire        mulhu_busy;
    wire        div_busy;
    wire        divu_busy;
    wire [63:0] mul_result;
    wire [65:0] mulhu_wide_result;

    // The divider uses a sign-magnitude interface. 33 bits are used so the
    // magnitude of the RV32 value -2^31 is representable without overflow.
    wire [31:0] a_magnitude;
    wire [31:0] b_magnitude;
    wire [32:0] div_x_signmag;
    wire [32:0] div_y_signmag;
    wire [32:0] divu_x_signmag;
    wire [32:0] divu_y_signmag;
    wire [32:0] div_quo_signmag;
    wire [32:0] div_rem_signmag;
    wire [32:0] divu_quo_signmag;
    wire [32:0] divu_rem_signmag;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire [31:0] divu_quotient;
    wire [31:0] divu_remainder;

    reg [4:0] op_r;
    reg       multi_launched;
    reg [31:0] multi_a;
    reg [31:0] multi_b;

    wire multi_op = (op == `ALU_MUL)   || (op == `ALU_MULH) ||
                    (op == `ALU_MULHU) || (op == `ALU_DIV)  ||
                    (op == `ALU_DIVU)  || (op == `ALU_REM)  ||
                    (op == `ALU_REMU);

    // busy is high in the launch cycle as well as while the selected unit is
    // running.  multi_launched prevents the held EX instruction from being
    // started a second time when the result becomes ready.
    assign busy = multi_op && (!multi_launched || mul_busy || mulhu_busy ||
                               div_busy || divu_busy);

    // A multi-cycle instruction starts once while the ALU is idle.
    assign mul_start   = ((op == `ALU_MUL) || (op == `ALU_MULH)) &&
                         !multi_launched;
    assign mulhu_start =  (op == `ALU_MULHU) && !multi_launched;
    assign div_start   = ((op == `ALU_DIV) || (op == `ALU_REM)) &&
                         !multi_launched;
    assign divu_start  = ((op == `ALU_DIVU) || (op == `ALU_REMU)) &&
                         !multi_launched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            op_r <= `ALU_ADD;
            multi_launched <= 1'b0;
            multi_a <= 32'h0;
            multi_b <= 32'h0;
        end else begin
            if (!multi_op)
                multi_launched <= 1'b0;
            else if (mul_start || mulhu_start || div_start || divu_start)
                multi_launched <= 1'b1;

            if (mul_start || mulhu_start || div_start || divu_start) begin
                op_r <= op;
                // Forwarding sources may leave MEM/WB while EX is stalled.
                // Preserve the operands used to launch the multi-cycle unit.
                multi_a <= a;
                multi_b <= b;
            end else if (!busy)
                op_r <= `ALU_ADD;
        end
    end

    assign a_magnitude = a[31] ? (~a + 32'd1) : a;
    assign b_magnitude = b[31] ? (~b + 32'd1) : b;
    assign div_x_signmag  = {a[31], a_magnitude};
    assign div_y_signmag  = {b[31], b_magnitude};
    assign divu_x_signmag = {1'b0, a};
    assign divu_y_signmag = {1'b0, b};

    // Convert sign-magnitude results back to RV32 two's-complement values.
    assign div_quotient = div_quo_signmag[32]
                        ? (~div_quo_signmag[31:0] + 32'd1)
                        : div_quo_signmag[31:0];
    assign div_remainder = div_rem_signmag[32]
                         ? (~div_rem_signmag[31:0] + 32'd1)
                         : div_rem_signmag[31:0];
    assign divu_quotient  = divu_quo_signmag[31:0];
    assign divu_remainder = divu_rem_signmag[31:0];

    always @(*) begin
        case (op_r)
            `ALU_MUL:   c = mul_result[31:0];
            `ALU_MULH:  c = mul_result[63:32];
            `ALU_MULHU: c = mulhu_wide_result[63:32];
            `ALU_DIV:   c = (multi_b == 0) ? 32'hffff_ffff :
                                 ((multi_a == 32'h8000_0000) &&
                                  (multi_b == 32'hffff_ffff))
                               ? 32'h8000_0000 : div_quotient;
            `ALU_DIVU:  c = (multi_b == 0) ? 32'hffff_ffff : divu_quotient;
            `ALU_REM:   c = (multi_b == 0) ? multi_a :
                                 ((multi_a == 32'h8000_0000) &&
                                  (multi_b == 32'hffff_ffff))
                               ? 32'h0 : div_remainder;
            `ALU_REMU:  c = (multi_b == 0) ? multi_a : divu_remainder;
            default: begin
                case (op)
                    `ALU_ADD: c = a + b;
                    `ALU_SUB: c = a - b;
                    `ALU_OR : c = a | b;
                    `ALU_XOR: c = a ^ b;
                    `ALU_AND: c = a & b;
                    `ALU_SLL: c = a << b[4:0];
                    `ALU_SRL: c = a >> b[4:0];
                    `ALU_SRA: c = $signed(a) >>> b[4:0];
                    `ALU_LT : c = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
                    `ALU_LTU: c = (a < b) ? 32'd1 : 32'd0;
                    `ALU_GE : c = ($signed(a) >= $signed(b)) ? 32'd1 : 32'd0;
                    `ALU_GEU: c = (a >= b) ? 32'd1 : 32'd0;
                    default : c = 32'd0;
                endcase
            end
        endcase
    end

    always @(*) begin
        case (op)
            `ALU_EQ : br = (a == b);
            `ALU_NE : br = (a != b);
            `ALU_LT : br = ($signed(a) < $signed(b));
            `ALU_LTU: br = (a < b);
            `ALU_GE : br = ($signed(a) >= $signed(b));
            `ALU_GEU: br = (a >= b);
            default : br = 1'b0;
        endcase
    end

    multiplier #(.WIDTH(32)) U_mul (
        .clk   (clk),
        .rst   (rst),
        .x     (a),
        .y     (b),
        .start (mul_start),
        .z     (mul_result),
        .busy  (mul_busy)
    );

    // Zero-extension to 33 bits makes Booth multiplication unsigned for MULHU.
    multiplier #(.WIDTH(33)) U_mulhu (
        .clk   (clk),
        .rst   (rst),
        .x     ({1'b0, a}),
        .y     ({1'b0, b}),
        .start (mulhu_start),
        .z     (mulhu_wide_result),
        .busy  (mulhu_busy)
    );

    divider #(.WIDTH(33)) U_div (
        .clk   (clk),
        .rst   (rst),
        .x     (div_x_signmag),
        .y     (div_y_signmag),
        .start (div_start),
        .z     (div_quo_signmag),
        .r     (div_rem_signmag),
        .busy  (div_busy)
    );

    divider #(.WIDTH(33)) U_divu (
        .clk   (clk),
        .rst   (rst),
        .x     (divu_x_signmag),
        .y     (divu_y_signmag),
        .start (divu_start),
        .z     (divu_quo_signmag),
        .r     (divu_rem_signmag),
        .busy  (divu_busy)
    );

endmodule

