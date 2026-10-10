`timescale 1ns / 1ps

module multiplier #(
    parameter WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [WIDTH-1:0]       x,
    input  wire [WIDTH-1:0]       y,
    input  wire                   start,
    output reg  [(2*WIDTH)-1:0]   z,
    output wire                   busy
);

    // 额外扩展一位，避免最小负数在 Booth 减法中无法取反的问题。
    localparam INNER_WIDTH = WIDTH + 1;
    localparam COUNT_WIDTH = (INNER_WIDTH <= 2) ? 1 : $clog2(INNER_WIDTH);
    localparam [COUNT_WIDTH-1:0] LAST_COUNT = INNER_WIDTH - 1;

    reg [INNER_WIDTH-1:0] multiplicand;
    reg [(2*INNER_WIDTH):0] product;
    reg [COUNT_WIDTH-1:0] count;
    reg busy_r;

    wire [INNER_WIDTH-1:0] upper_product;
    wire [INNER_WIDTH-1:0] add_result;
    wire [(2*INNER_WIDTH):0] next_product;

    assign busy = busy_r;
    assign upper_product = product[2*INNER_WIDTH:INNER_WIDTH+1];

    // Booth 编码：01 加被乘数，10 减被乘数，00/11 保持。
    assign add_result = (product[1:0] == 2'b01)
                      ? upper_product + multiplicand
                      : (product[1:0] == 2'b10)
                      ? upper_product - multiplicand
                      : upper_product;

    // 将 A、Q、Q-1 整体算术右移一位。
    assign next_product = {
        add_result[INNER_WIDTH-1],
        add_result,
        product[INNER_WIDTH:1]
    };

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            multiplicand <= {INNER_WIDTH{1'b0}};
            product      <= {(2*INNER_WIDTH+1){1'b0}};
            count        <= {COUNT_WIDTH{1'b0}};
            z            <= {(2*WIDTH){1'b0}};
            busy_r       <= 1'b0;
        end else if (!busy_r) begin
            if (start) begin
                multiplicand <= {x[WIDTH-1], x};
                product      <= {
                    {INNER_WIDTH{1'b0}},
                    y[WIDTH-1], y,
                    1'b0
                };
                count        <= {COUNT_WIDTH{1'b0}};
                busy_r       <= 1'b1;
            end
        end else begin
            product <= next_product;

            if (count == LAST_COUNT) begin
                z      <= next_product[2*WIDTH:1];
                busy_r <= 1'b0;
            end else begin
                count <= count + 1'b1;
            end
        end
    end

endmodule

