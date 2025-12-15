// 协助计算tan(a)的除法器, a是整数角度
// 所以输出
// 最小值是 tan(1°) = 0.017455064
// 最大值是 tan(89°) = 57.28996163
// 本除法器的输入是 sin(a) 和 cos(a) 的 BF16 格式表示
// 输出是 tan(a) 的 BF16 格式表示

`timescale 1ns / 1ps

module bf16_divider (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [15:0] a,    // BF16: 1s, 8e, 7m
    input  wire [15:0] b,    // BF16: 1s, 8e, 7m
    output reg  [15:0] result,
    output reg  error,
    output reg  done
);
    // 状态机
    reg [3:0] state;
    localparam IDLE       = 4'd0,
               DECODE     = 4'd1,
               DIV_INIT   = 4'd2,
               DIV_ITER   = 4'd3,
               DIV_ITER2  = 4'd4,
               DIV_NORM   = 4'd5,
               OUTPUT     = 4'd6;

    // 寄存器
    reg a_sign_reg, b_sign_reg;
    reg [7:0] a_exp_reg, b_exp_reg;
    reg [7:0] a_mant_full_reg, b_mant_full_reg;
    reg special_case_flag;
    reg [15:0] special_case_result;

    reg result_sign_reg;
    reg signed [9:0] result_exp_reg;

    reg [15:0] div_rem_reg [0:3];
    reg [15:0] div_quo_reg [0:3];
    reg [7:0]  numerator_reg [0:3];
    reg [7:0]  denominator_reg;

    reg [3:0] iter_cnt;

    // 归一化临时寄存器
    reg [7:0] norm_mant_full;
    reg signed [1:0] norm_exp_adj;
    reg signed [9:0] temp_exp;

    // 特殊值检测
    wire a_is_zero = (a[14:7]==0) && (a[6:0]==0);
    wire b_is_zero = (b[14:7]==0) && (b[6:0]==0);
    wire a_is_inf  = (a[14:7]==8'hFF) && (a[6:0]==0);
    wire b_is_inf  = (b[14:7]==8'hFF) && (b[6:0]==0);
    wire a_is_nan  = (a[14:7]==8'hFF) && (a[6:0]!=0);
    wire b_is_nan  = (b[14:7]==8'hFF) && (b[6:0]!=0);

    wire special_case_nan        = a_is_nan || b_is_nan;
    wire special_case_inf_a      = a_is_inf && !b_is_inf;
    wire special_case_inf_b      = !a_is_inf && b_is_inf;
    wire special_case_zero_a     = a_is_zero && !b_is_zero;
    wire special_case_inf_div_inf= a_is_inf && b_is_inf;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            result <= 16'h0000;
            error <= 0;
            done <= 0;
            special_case_flag <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    error <= 0;
                    special_case_flag <= 0;
                    if (start) state <= DECODE;
                end

                DECODE: begin
                    // 缓存输入
                    a_sign_reg <= a[15];
                    b_sign_reg <= b[15];
                    a_exp_reg  <= a[14:7];
                    b_exp_reg  <= b[14:7];

                    // 尾数含隐含位
                    a_mant_full_reg <= (a[14:7]==0) ? {1'b0, a[6:0]} : {1'b1, a[6:0]};
                    b_mant_full_reg <= (b[14:7]==0) ? {1'b0, b[6:0]} : {1'b1, b[6:0]};

                    // 特殊值处理
                    if (special_case_nan || (a_is_zero && b_is_zero) || special_case_inf_div_inf) begin
                        special_case_result <= 16'hFFC0; // NaN
                        special_case_flag <= 1;
                        state <= DIV_NORM;
                    end else if (b_is_zero) begin
                        special_case_result <= {a[15]^b[15], 8'hFF, 7'h00}; // Inf
                        special_case_flag <= 1;
                        error <= 1;
                        state <= DIV_NORM;
                    end else if (special_case_zero_a) begin
                        special_case_result <= {a[15]^b[15], 8'h00, 7'h00}; // 0
                        special_case_flag <= 1;
                        state <= DIV_NORM;
                    end else if (special_case_inf_a) begin
                        special_case_result <= {a[15]^b[15], 8'hFF, 7'h00}; // Inf
                        special_case_flag <= 1;
                        state <= DIV_NORM;
                    end else if (special_case_inf_b) begin
                        special_case_result <= {a[15]^b[15], 8'h00, 7'h00}; // 0
                        special_case_flag <= 1;
                        state <= DIV_NORM;
                    end else begin
                        // 正常路径
                        result_sign_reg <= a[15] ^ b[15];
                        result_exp_reg  <= $signed({2'b0, a[14:7]}) - $signed({2'b0, b[14:7]}) + 10'sd127;
                        denominator_reg <= b_mant_full_reg;

                        div_rem_reg[0] <= 0;
                        div_quo_reg[0] <= 0;
                        numerator_reg[0] <= a_mant_full_reg;
                        iter_cnt <= 0;
                        state <= DIV_INIT;
                    end
                end

                DIV_INIT: begin
                    // 第一次移位
                    div_rem_reg[1] <= {div_rem_reg[0][14:0], numerator_reg[0][7]};
                    numerator_reg[1] <= {numerator_reg[0][6:0], 1'b0};
                    state <= DIV_ITER;
                end

                DIV_ITER: begin
                    // 比较与减法
                    if (div_rem_reg[1] >= {8'b0, denominator_reg}) begin
                        div_rem_reg[2] <= div_rem_reg[1] - {8'b0, denominator_reg};
                        div_quo_reg[1] <= {div_quo_reg[0][14:0], 1'b1};
                    end else begin
                        div_rem_reg[2] <= div_rem_reg[1];
                        div_quo_reg[1] <= {div_quo_reg[0][14:0], 1'b0};
                    end
                    numerator_reg[2] <= numerator_reg[1];
                    iter_cnt <= iter_cnt + 1;
                    state <= DIV_ITER2;
                end

                DIV_ITER2: begin
                    // 下一级移位
                    div_rem_reg[3] <= {div_rem_reg[2][14:0], numerator_reg[2][7]};
                    numerator_reg[3] <= {numerator_reg[2][6:0], 1'b0};

                    if (iter_cnt < 4'd15) begin
                        // 继续循环
                        div_rem_reg[0] <= div_rem_reg[3];
                        div_quo_reg[0] <= div_quo_reg[1];
                        numerator_reg[0] <= numerator_reg[3];
                        state <= DIV_ITER;
                    end else begin
                        // 最后一次比较
                        if (div_rem_reg[3] >= {8'b0, denominator_reg})
                            div_quo_reg[2] <= {div_quo_reg[1][14:0], 1'b1};
                        else
                            div_quo_reg[2] <= {div_quo_reg[1][14:0], 1'b0};
                        state <= DIV_NORM;
                    end
                end

                DIV_NORM: begin
                    if (special_case_flag) begin
                        result <= special_case_result;
                        state <= OUTPUT;
                    end else begin
                        // 归一化
                        if (div_quo_reg[2][15]) begin
                            norm_mant_full = div_quo_reg[2][15:8];
                            norm_exp_adj   = 0;
                        end else begin
                            norm_mant_full = div_quo_reg[2][14:7];
                            norm_exp_adj   = -1;
                        end

                        temp_exp = result_exp_reg + norm_exp_adj;

                        if (temp_exp >= 10'sd255) begin
                            result <= {result_sign_reg, 8'hFF, 7'h00};
                            error  <= 1;
                        end else if (temp_exp <= 0) begin
                            result <= {result_sign_reg, 8'h00, 7'h00};
                        end else begin
                            result <= {result_sign_reg, temp_exp[7:0], norm_mant_full[6:0]};
                        end
                        state <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    done <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule