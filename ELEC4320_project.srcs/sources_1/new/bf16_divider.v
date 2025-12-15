// 协助计算tan(a)的除法器, a是整数角度
// 所以输出
// 最小值是 tan(1°) = 0.017455064
// 最大值是 tan(89°) = 57.28996163
// 本除法器的输入是 sin(a) 和 cos(a) 的 BF16 格式表示
// 输出是 tan(a) 的 BF16 格式表示

`timescale 1ns / 1ps

// 协助计算tan(a)的除法器, a是整数角度
// 输入：sin(a)、cos(a) 的 BF16；输出：tan(a) 的 BF16
module bf16_divider (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [15:0] a,      // BF16: 1s, 8e, 7m
    input  wire [15:0] b,      // BF16: 1s, 8e, 7m
    output reg  [15:0] result, // BF16: 1s, 8e, 7m
    output reg         error,
    output reg         done
);

localparam IDLE = 2'b00;
localparam CALC = 2'b01;
localparam NORM = 2'b10;
localparam DONE = 2'b11;

reg [1:0]  state;
reg [15:0] a_reg, b_reg;
reg        sign_reg;
reg [8:0]  exp_reg;       // 扩展1位用于溢出检测
reg [31:0] mant_div_reg;  // 保存尾数除法结果（含额外小数位）
reg [6:0]  mant_result;

wire a_sign, b_sign, result_sign;
wire [7:0] a_exp, b_exp;
wire [6:0] a_mant, b_mant;
wire a_zero, b_zero, a_inf, b_inf, a_nan, b_nan;
wire [23:0] dividend, divisor;  // 带隐含位的尾数
wire [7:0]  exp_diff;

// 提取各部分
assign a_sign = a[15];
assign b_sign = b[15];
assign a_exp  = a[14:7];
assign b_exp  = b[14:7];
assign a_mant = a[6:0];
assign b_mant = b[6:0];

// 特殊值检测
assign a_zero = (a_exp == 8'h00) && (a_mant == 7'h00);
assign b_zero = (b_exp == 8'h00) && (b_mant == 7'h00);
assign a_inf  = (a_exp == 8'hFF) && (a_mant == 7'h00);
assign b_inf  = (b_exp == 8'hFF) && (b_mant == 7'h00);
assign a_nan  = (a_exp == 8'hFF) && (a_mant != 7'h00);
assign b_nan  = (b_exp == 8'hFF) && (b_mant != 7'h00);

// 符号计算
assign result_sign = a_sign ^ b_sign;

// 尾数扩展（添加隐含位）
assign dividend = (a_exp == 8'h00) ? {1'b0, a_mant, 16'h0} : {1'b1, a_mant, 16'h0};
assign divisor  = (b_exp == 8'h00) ? {1'b0, b_mant, 16'h0} : {1'b1, b_mant, 16'h0};

// 指数差计算：e_a - e_b + bias
assign exp_diff = {1'b0, a_exp} - {1'b0, b_exp} + 8'd127;

// 24-bit 前导 1 位置（返回 0..24，24 表示全 0）
function [4:0] clz24;
    input [23:0] val;
    integer i;
    begin
        clz24 = 5'd24;
        for (i = 23; i >= 0; i = i - 1) begin
            if (val[i]) begin
                clz24 = 5'(23 - i);
                disable clz24;
            end
        end
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state        <= IDLE;
        a_reg        <= 16'h0;
        b_reg        <= 16'h0;
        sign_reg     <= 1'b0;
        exp_reg      <= 9'h0;
        mant_div_reg <= 32'h0;
        mant_result  <= 7'h0;
        result       <= 16'h0;
        error        <= 1'b0;
        done         <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                done  <= 1'b0;
                error <= 1'b0;
                if (start) begin
                    a_reg    <= a;
                    b_reg    <= b;
                    sign_reg <= result_sign;
                    // 处理特殊情况
                    if (b_zero && !a_zero && !a_nan) begin
                        result <= {result_sign, 8'hFF, 7'h00}; // 除以零 -> Inf
                        error  <= 1'b1;
                        done   <= 1'b1;
                        state  <= DONE;
                    end else if (a_nan || b_nan) begin
                        result <= 16'h7FC0; // NaN
                        error  <= 1'b1;
                        done   <= 1'b1;
                        state  <= DONE;
                    end else if (a_inf && b_inf) begin
                        result <= 16'h7FC0; // Inf/Inf -> NaN
                        error  <= 1'b1;
                        done   <= 1'b1;
                        state  <= DONE;
                    end else if (a_inf) begin
                        result <= {result_sign, 8'hFF, 7'h00};
                        done   <= 1'b1;
                        state  <= DONE;
                    end else if (b_inf) begin
                        result <= {result_sign, 8'h00, 7'h00};
                        done   <= 1'b1;
                        state  <= DONE;
                    end else if (a_zero && !b_zero) begin
                        result <= {result_sign, 8'h00, 7'h00};
                        done   <= 1'b1;
                        state  <= DONE;
                    end else if (a_zero && b_zero) begin
                        result <= 16'h7FC0; // 0/0 -> NaN
                        error  <= 1'b1;
                        done   <= 1'b1;
                        state  <= DONE;
                    end else begin
                        // 正常计算路径
                        exp_reg      <= {1'b0, exp_diff};
                        mant_div_reg <= 32'h0;
                        state        <= CALC;
                    end
                end
            end

            CALC: begin
                // 尾数除法，左移 8 位保留更多小数精度
                if (divisor != 24'h0)
                    mant_div_reg <= (dividend << 8) / divisor; // 结果位宽约 24+8=32
                else
                    mant_div_reg <= 32'h0;
                state <= NORM;
            end

            NORM: begin
                // 取有效 24 位进行归一化
                reg [23:0] mant24;
                reg [4:0]  lz;
                reg [8:0]  exp_adj;
                reg [23:0] mant_norm;
                mant24   = mant_div_reg[31:8];

                if (mant24 == 0) begin
                    // 结果为 0
                    result <= {sign_reg, 8'h00, 7'h00};
                    error  <= 1'b0;
                end else begin
                    lz = clz24(mant24);
                    // 目标：最高位对齐到 bit23（1.x）
                    if (lz > 23) lz = 23;
                    // 向左移：减指数；向右移：加指数
                    if (lz != 0)
                        mant_norm = mant24 << lz;
                    else
                        mant_norm = mant24;
                    exp_adj = exp_reg - lz;

                    // 取 BF16 尾数（截断）
                    mant_result = mant_norm[22:16];

                    // 溢出 / 下溢检查
                    if (exp_adj[8] || exp_adj[7:0] == 8'hFF) begin
                        result <= {sign_reg, 8'hFF, 7'h00};
                        error  <= 1'b1;
                    end else if (exp_adj[7:0] == 8'h00) begin
                        // 下溢到 0
                        result <= {sign_reg, 8'h00, 7'h00};
                        error  <= 1'b1;
                    end else begin
                        result <= {sign_reg, exp_adj[7:0], mant_result};
                        error  <= 1'b0;
                    end
                end

                done  <= 1'b1;
                state <= DONE;
            end

            DONE: begin
                done  <= 1'b0;  // 拉高一个周期后清零
                state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule