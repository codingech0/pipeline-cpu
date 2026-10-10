`timescale 1ns / 1ps

module divider #(
    parameter WIDTH = 32
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire [WIDTH-1:0]     x,
    input  wire [WIDTH-1:0]     y,
    input  wire                 start,
    output wire [WIDTH-1:0]     z,
    output reg  [WIDTH-1:0]     r,
    output reg                  busy
);

    // 原码格式：最高位是符号位，其余位是数值位。
    // WIDTH 必须不小于 2。
    localparam COUNT_WIDTH = (WIDTH <= 2) ? 1 : $clog2(WIDTH);
    localparam [COUNT_WIDTH-1:0] LAST_COUNT = WIDTH - 1;

    // rem 是 WIDTH+1 位补码形式的部分余数，rem[WIDTH] 为符号位。
    reg [WIDTH:0]   rem;
    reg [WIDTH-1:0] quo;
    reg [WIDTH-1:0] divisor;
    reg [COUNT_WIDTH-1:0] count;

    reg quotient_negative;
    reg remainder_negative;
    reg [WIDTH-1:0] z_reg;

    wire [WIDTH:0]   divisor_ext;
    wire [WIDTH:0]   shifted_rem;
    wire [WIDTH:0]   trial_rem;
    wire [WIDTH:0]   corrected_rem;
    wire [WIDTH-1:0] next_quo;
    wire [WIDTH-1:0] result_quo;
    wire [WIDTH-1:0] result_rem;

    assign z = z_reg;

    assign divisor_ext = {1'b0, divisor};

    // 部分余数和商整体左移一位。
    assign shifted_rem = {rem[WIDTH-1:0], quo[WIDTH-1]};

    // 加减交替法：上一次部分余数为负则加除数，否则减除数。
    assign trial_rem = rem[WIDTH]
                     ? shifted_rem + divisor_ext
                     : shifted_rem - divisor_ext;

    // 本次部分余数非负时，上商 1；否则上商 0。
    assign next_quo = {
        quo[WIDTH-2:0],
        ~trial_rem[WIDTH]
    };

    // 最后一次运算后，若余数为负则恢复一次。
    assign corrected_rem = trial_rem[WIDTH]
                         ? trial_rem + divisor_ext
                         : trial_rem;

    // 恢复原码符号。结果为 0 时统一输出正零。
    assign result_quo = {
        quotient_negative && (|next_quo[WIDTH-2:0]),
        next_quo[WIDTH-2:0]
    };

    assign result_rem = {
        remainder_negative && (|corrected_rem[WIDTH-2:0]),
        corrected_rem[WIDTH-2:0]
    };

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rem                <= {(WIDTH+1){1'b0}};
            quo                <= {WIDTH{1'b0}};
            divisor            <= {WIDTH{1'b0}};
            count              <= {COUNT_WIDTH{1'b0}};
            quotient_negative  <= 1'b0;
            remainder_negative <= 1'b0;
            z_reg              <= {WIDTH{1'b0}};
            r                  <= {WIDTH{1'b0}};
            busy               <= 1'b0;
        end else if (!busy) begin
            if (start) begin
                if (y[WIDTH-2:0] == {(WIDTH-1){1'b0}}) begin
                    // 除数为正零或负零。接口没有除零标志，因此商置为
                    // 最大正原码，余数保持为被除数。
                    z_reg <= {1'b0, {(WIDTH-1){1'b1}}};
                    r     <= x;
                    busy  <= 1'b0;
                end else begin
                    rem     <= {(WIDTH+1){1'b0}};
                    quo     <= {1'b0, x[WIDTH-2:0]};
                    divisor <= {1'b0, y[WIDTH-2:0]};

                    quotient_negative  <= x[WIDTH-1] ^ y[WIDTH-1];
                    remainder_negative <= x[WIDTH-1];
                    count              <= {COUNT_WIDTH{1'b0}};
                    busy               <= 1'b1;
                end
            end
        end else begin
            rem <= trial_rem;
            quo <= next_quo;

            if (count == LAST_COUNT) begin
                z_reg <= result_quo;
                r     <= result_rem;
                busy  <= 1'b0;
            end else begin
                count <= count + 1'b1;
            end
        end
    end

endmodule

