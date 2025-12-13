    // arcsin alu_asin (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_ASIN)),
    //     .a(a_val),
    //     .result(asin_result),
    //     .error(asin_error),
    //     .done(asin_done)
    // );

    //要求
    //输入是整数斜率，[-999,999]
    //输出是BF16浮点数格式，表示角度
    //实际上在整数情况下，arcsin只有-1，0，1三个有效输入
    //用if-else实现
    //如果是其他情况直接error就可以了

`timescale 1ns / 1ps
`include "define.vh"

module arcsin (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer slope [-999,999]
    output reg  [`INPUTOUTBIT-1:0] result,     // BF16 angle in degrees
    output reg  error,
    output reg  done
);
    // States
    reg [1:0] state;
    localparam IDLE = 2'd0, DONE_ST = 2'd1;

    // Precomputed BF16 values
    localparam BF16_NEG_90 = 16'hC2DA;  // -90.0
    localparam BF16_ZERO   = 16'h0000;  // 0.0
    localparam BF16_POS_90 = 16'h42DA;  // 90.0
    localparam BF16_NAN    = 16'hFFC0;  // NaN

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state  <= IDLE;
            result <= 0;
            error  <= 0;
            done   <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start) begin
                        if (a > 16'sd999 || a < -16'sd999) begin
                            error  <= 1;
                            result <= BF16_NAN;
                        end else if (a == -16'sd1) begin
                            result <= BF16_NEG_90;
                            error  <= 0;
                        end else if (a == 16'sd0) begin
                            result <= BF16_ZERO;
                            error  <= 0;
                        end else if (a == 16'sd1) begin
                            result <= BF16_POS_90;
                            error  <= 0;
                        end else begin
                            error  <= 1;
                            result <= BF16_NAN;
                        end
                        done  <= 1;
                        state <= DONE_ST;
                    end
                end

                DONE_ST: begin
                    done <= 1;
                    if (!start) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule