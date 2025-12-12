`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 15:46:22
// Design Name: 
// Module Name: alu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module alu(
    input wire clk,
    input wire rst,
    input wire [3:0] sw,
    input wire btn_left,
    input wire btn_right,
    input wire btn_up,
    input wire btn_down,
    input wire btn_mid,
    output wire [6:0] seg,
    output wire [3:0] an,
    output reg [`INPUTOUTBIT-1:0] result, // IEEE754 floating point output
    output reg error, // 1 = have error, 0 = no error
    output reg cal_done
);

    // State machine states
    localparam IDLE = 3'b000;
    localparam INPUT_A = 3'b001;
    localparam INPUT_B = 3'b010;
    localparam COMPUTE = 3'b011;
    localparam WAIT_RESULT = 3'b100;
    localparam OUTPUT = 3'b101;

    reg [2:0] state;
    reg signed [`INPUTOUTBIT-1:0] a_val;
    reg signed [`INPUTOUTBIT-1:0] b_val;
    reg [3:0] sw_reg;
    wire signed [`INPUTOUTBIT-1:0] input_val;
    wire input_done;
    reg reset_input;
    reg op_start;

    // Synchronize input_done to fast clock domain
    reg input_done_sync1, input_done_sync2, input_done_prev;
    wire input_done_edge;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            input_done_sync1 <= 0;
            input_done_sync2 <= 0;
            input_done_prev <= 0;
        end else begin
            input_done_sync1 <= input_done;
            input_done_sync2 <= input_done_sync1;
            input_done_prev <= input_done_sync2;
        end
    end

    assign input_done_edge = input_done_sync2 & ~input_done_prev;

    // Operation module outputs
    wire [`INPUTOUTBIT-1:0] add_result, sub_result, mul_result, div_result, sqrt_result, cos_result, sin_result, tan_result, asin_result, acos_result, atan_result, exp_result, fac_result, log_result, pow_result;
    wire add_done, sub_done, mul_done, div_done, sqrt_done, cos_done, sin_done, tan_done, asin_done, acos_done, atan_done, exp_done, fac_done, log_done, pow_done;
    wire add_error, sub_error, mul_error, div_error, sqrt_error, cos_error, sin_error, tan_error, asin_error, acos_error, atan_error, exp_error, fac_error, log_error, pow_error;

    // I/O Controller
    input_output_controller io_ctrl (
        .clk(clk),
        .rst(rst),
        .reset_input(reset_input),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .btn_up(btn_up),
        .btn_down(btn_down),
        .btn_mid(btn_mid),
        .seg(seg),
        .an(an),
        .input_val(input_val),
        .input_done(input_done)
    );

    // Operation Modules
    add alu_add (
        .clk(clk),
        .rst(rst),
        .start(op_start && (sw_reg == `OP_ADD)),
        .a(a_val),
        .b(b_val),
        .result(add_result),
        .error(add_error),
        .done(add_done)
    );

    sub alu_sub (
        .clk(clk),
        .rst(rst),
        .start(op_start && (sw_reg == `OP_SUB)),
        .a(a_val),
        .b(b_val),
        .result(sub_result),
        .error(sub_error),
        .done(sub_done)
    );

     mul alu_mul (
         .clk(clk),
         .rst(rst),
         .start(op_start && (sw_reg == `OP_MUL)),
         .a(a_val),
         .b(b_val),
         .result(mul_result),
         .error(mul_error),
         .done(mul_done)
     );

    // div alu_div (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_DIV)),
    //     .a(a_val),
    //     .b(b_val),
    //     .result(div_result),
    //     .error(div_error),
    //     .done(div_done)
    // );

    // sqrt alu_sqrt (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_SQRT)),
    //     .a(a_val),
    //     .result(sqrt_result),
    //     .error(sqrt_error),
    //     .done(sqrt_done)
    // );

    // cos alu_cos (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_COS)),
    //     .a(a_val),
    //     .result(cos_result),
    //     .error(cos_error),
    //     .done(cos_done)
    // );

    // sin alu_sin (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_SIN)),
    //     .a(a_val),
    //     .result(sin_result),
    //     .error(sin_error),
    //     .done(sin_done)
    // );

    // tan alu_tan (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_TAN)),
    //     .a(a_val),
    //     .result(tan_result),
    //     .error(tan_error),
    //     .done(tan_done)
    // );

    // arcsin alu_asin (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_ASIN)),
    //     .a(a_val),
    //     .result(asin_result),
    //     .error(asin_error),
    //     .done(asin_done)
    // );

    // arccos alu_acos (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_ACOS)),
    //     .a(a_val),
    //     .result(acos_result),
    //     .error(acos_error),
    //     .done(acos_done)
    // );

    // arctan alu_atan (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_ATAN)),
    //     .a(a_val),
    //     .result(atan_result),
    //     .error(atan_error),
    //     .done(atan_done)
    // );

    // exp alu_exp (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_EXP)),
    //     .a(a_val),
    //     .result(exp_result),
    //     .error(exp_error),
    //     .done(exp_done)
    // );

    // fac alu_fac (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_FAC)),
    //     .a(a_val),
    //     .result(fac_result),
    //     .error(fac_error),
    //     .done(fac_done)
    // );

    // log alu_log (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_LOG)),
    //     .a(a_val),
    //     .b(b_val),
    //     .result(log_result),
    //     .error(log_error),
    //     .done(log_done)
    // );

    // pow alu_pow (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_POW)),
    //     .a(a_val),
    //     .b(b_val),
    //     .result(pow_result),
    //     .error(pow_error),
    //     .done(pow_done)
    // );

    // State machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            a_val <= 0;
            b_val <= 0;
            sw_reg <= 0;
            reset_input <= 0;
            op_start <= 0;
            result <= 0;
            cal_done <= 0;
        end else begin
            reset_input <= 0;
            op_start <= 0;
            cal_done <= 0;

            case (state)
                IDLE: begin
                    sw_reg <= sw;  // Latch the operation
                    if (input_done_edge) begin
                        a_val <= input_val;
                        reset_input <= 1;
                        // Check if operation needs one or two operands
                        case (sw_reg)
                            `OP_ADD, `OP_SUB, `OP_MUL, `OP_DIV, `OP_LOG, `OP_POW: begin
                                // Two operand operations
                                state <= INPUT_B;
                            end
                            `OP_SQRT, `OP_COS, `OP_SIN, `OP_TAN, `OP_ACOS, `OP_ASIN, `OP_ATAN, `OP_EXP, `OP_FAC: begin
                                // Single operand operations
                                state <= COMPUTE;
                            end
                            default: state <= INPUT_B;
                        endcase
                    end
                end

                INPUT_B: begin
                    if (input_done_edge) begin
                        b_val <= input_val;
                        reset_input <= 1;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    op_start <= 1;
                    state <= WAIT_RESULT;
                end

                WAIT_RESULT: begin
                    // Check which operation completed based on sw_reg
                    case (sw_reg)
                        `OP_ADD: begin
                            if (add_done) begin
                                result <= add_result;
                                error <= add_error;
                                cal_done <= 1;
                                state <= OUTPUT;
                            end
                        end
                        `OP_SUB: begin
                            if (sub_done) begin
                                result <= sub_result;
                                error <= sub_error;
                                cal_done <= 1;
                                state <= OUTPUT;
                            end
                        end
                        // `OP_MUL: begin
                        //     if (mul_done) begin
                        //         result <= mul_result;
                        //         error <= mul_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_DIV: begin
                        //     if (div_done) begin
                        //         result <= div_result;
                        //         error <= div_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_SQRT: begin
                        //     if (sqrt_done) begin
                        //         result <= sqrt_result;
                        //         error <= sqrt_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_COS: begin
                        //     if (cos_done) begin
                        //         result <= cos_result;
                        //         error <= cos_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_SIN: begin
                        //     if (sin_done) begin
                        //         result <= sin_result;
                        //         error <= sin_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_TAN: begin
                        //     if (tan_done) begin
                        //         result <= tan_result;
                        //         error <= tan_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_ASIN: begin
                        //     if (asin_done) begin
                        //         result <= asin_result;
                        //         error <= asin_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_ACOS: begin
                        //     if (acos_done) begin
                        //         result <= acos_result;
                        //         error <= acos_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_ATAN: begin
                        //     if (atan_done) begin
                        //         result <= atan_result;
                        //         error <= atan_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_EXP: begin
                        //     if (exp_done) begin
                        //         result <= exp_result;
                        //         error <= exp_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_FAC: begin
                        //     if (fac_done) begin
                        //         result <= fac_result;
                        //         error <= fac_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_LOG: begin
                        //     if (log_done) begin
                        //         result <= log_result;
                        //         error <= log_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        // `OP_POW: begin
                        //     if (pow_done) begin
                        //         result <= pow_result;
                        //         error <= pow_error;
                        //         cal_done <= 1;
                        //         state <= OUTPUT;
                        //     end
                        // end
                        
                        default: state <= IDLE;
                    endcase
                end

                OUTPUT: begin
                    // Hold result for one cycle
                    cal_done <= 1;
                    // state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
