//`define INPUTOUTBIT 16

`timescale 1ns / 1ps
`include "define.vh"

module sin(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,
    output reg  signed [`INPUTOUTBIT-1:0] result, // sin * 1e-4
    output reg  done
);
    localparam integer QSHIFT      = 29;
    localparam integer MUL_LATENCY = 2; // cycles between mul_en and mul_pipe valid

    localparam signed [15:0] DEG_180  = 16'sd180;
    localparam signed [15:0] DEG_360  = 16'sd360;
    localparam signed [15:0] DEG_90   = 16'sd90;
    localparam signed [31:0] DEG2RAD_Q29 = 32'sd9370197;

    localparam signed [31:0] COEF_C1 = 32'sd536870912;
    localparam signed [31:0] COEF_C3 = -32'sd89478485;
    localparam signed [31:0] COEF_C5 = 32'sd4473924;
    localparam signed [31:0] COEF_C7 = -32'sd106177;
    localparam signed [63:0] ROUND_CONST = 64'sd1 << (QSHIFT-1);

    localparam [4:0]
        IDLE        = 5'd0,
        PRE_WRAP    = 5'd1,
        PRE_SIGN    = 5'd2,
        PRE_REF     = 5'd3,
        RAD_CONV    = 5'd4,
        X_LOAD      = 5'd5,
        X_MUL       = 5'd6,
        X_PIPE      = 5'd7,
        HORNER3_LOAD= 5'd8,
        HORNER3_MUL = 5'd9,
        HORNER3_ACC = 5'd10,
        HORNER2_LOAD= 5'd11,
        HORNER2_MUL = 5'd12,
        HORNER2_ACC = 5'd13,
        HORNER1_LOAD= 5'd14,
        HORNER1_MUL = 5'd15,
        HORNER1_ACC = 5'd16,
        FINAL_MUL   = 5'd17,
        FINAL_PIPE  = 5'd18,
        SCALE_LOAD  = 5'd19,
        SCALE_EXEC  = 5'd20,
        SCALE_SAVE  = 5'd21,
        SCALE_ROUND = 5'd22,
        SCALE_OUT   = 5'd23,
        MUL_WAIT    = 5'd24;

    reg [4:0] state, state_after_mul;

    reg sign_flag;
    reg signed [15:0] angle_norm;
    reg signed [15:0] angle_abs;
    reg signed [15:0] angle_ref_deg;

    reg signed [31:0] x_q;
    reg signed [31:0] x2_q;
    reg signed [31:0] poly_reg;
    reg signed [31:0] sin_q;
    reg signed [63:0] scale_prod;
    reg signed [63:0] scale_round;
    reg signed [31:0] milli_val;

    reg signed [31:0] mul_a_reg, mul_b_reg;
    reg signed [31:0] mul_stage_a, mul_stage_b;
    reg signed [31:0] mul_feed_a,  mul_feed_b;
    reg               mul_en, mul_issue_d, mul_issue_q;
    reg signed [63:0] mul_pipe;
    reg [1:0]         mul_wait_cnt;

    wire signed [31:0] mul_shr = mul_pipe >>> QSHIFT;
    wire signed [15:0] angle_abs_sat = (angle_abs > DEG_180) ? DEG_180 : angle_abs;

    // Three-stage shared multiplier (regs before DSP input)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mul_stage_a <= 32'sd0;
            mul_stage_b <= 32'sd0;
            mul_feed_a  <= 32'sd0;
            mul_feed_b  <= 32'sd0;
            mul_issue_d <= 1'b0;
            mul_issue_q <= 1'b0;
            mul_pipe    <= 64'sd0;
        end else begin
            mul_issue_d <= mul_en;
            mul_issue_q <= mul_issue_d;

            if (mul_en) begin
                mul_stage_a <= mul_a_reg;
                mul_stage_b <= mul_b_reg;
            end
            if (mul_issue_d) begin
                mul_feed_a <= mul_stage_a;
                mul_feed_b <= mul_stage_b;
            end
            if (mul_issue_q)
                mul_pipe <= mul_feed_a * mul_feed_b;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= IDLE;
            state_after_mul <= IDLE;
            mul_wait_cnt    <= 0;
            sign_flag       <= 1'b0;
            angle_norm      <= 16'sd0;
            angle_abs       <= 16'sd0;
            angle_ref_deg   <= 16'sd0;
            x_q             <= 32'sd0;
            x2_q            <= 32'sd0;
            poly_reg        <= 32'sd0;
            sin_q           <= 32'sd0;
            scale_prod      <= 64'sd0;
            scale_round     <= 64'sd0;
            milli_val       <= 32'sd0;
            mul_a_reg       <= 32'sd0;
            mul_b_reg       <= 32'sd0;
            mul_en          <= 1'b0;
            result          <= 0;
            done            <= 0;
        end else begin
            mul_en <= 1'b0;
            done   <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) state <= PRE_WRAP;
                end

                PRE_WRAP: begin
                    if (a >  DEG_180)      angle_norm <= a - DEG_360;
                    else if (a < -DEG_180) angle_norm <= a + DEG_360;
                    else                   angle_norm <= a;
                    state <= PRE_SIGN;
                end

                PRE_SIGN: begin
                    sign_flag <= (angle_norm < 0);
                    angle_abs <= angle_norm[15] ? (16'sd0 - angle_norm) : angle_norm;
                    state <= PRE_REF;
                end

                PRE_REF: begin
                    angle_abs <= angle_abs_sat;
                    if (angle_abs_sat > DEG_90)
                        angle_ref_deg <= DEG_180 - angle_abs_sat;
                    else
                        angle_ref_deg <= angle_abs_sat;
                    state <= RAD_CONV;
                end

                RAD_CONV: begin
                    x_q   <= angle_ref_deg * DEG2RAD_Q29;
                    state <= X_LOAD;
                end

                X_LOAD: begin
                    mul_a_reg <= x_q;
                    mul_b_reg <= x_q;
                    state     <= X_MUL;
                end

                X_MUL: begin
                    mul_en          <= 1'b1;
                    mul_wait_cnt    <= MUL_LATENCY;
                    state_after_mul <= X_PIPE;
                    state           <= MUL_WAIT;
                end

                X_PIPE: begin
                    x2_q  <= mul_shr;
                    state <= HORNER3_LOAD;
                end

                HORNER3_LOAD: begin
                    poly_reg  <= COEF_C7;
                    mul_a_reg <= x2_q;
                    mul_b_reg <= COEF_C7;
                    state     <= HORNER3_MUL;
                end

                HORNER3_MUL: begin
                    mul_en          <= 1'b1;
                    mul_wait_cnt    <= MUL_LATENCY;
                    state_after_mul <= HORNER3_ACC;
                    state           <= MUL_WAIT;
                end

                HORNER3_ACC: begin
                    poly_reg  <= COEF_C5 + mul_shr;
                    mul_a_reg <= x2_q;
                    mul_b_reg <= COEF_C5 + mul_shr;
                    state     <= HORNER2_MUL;
                end

                HORNER2_MUL: begin
                    mul_en          <= 1'b1;
                    mul_wait_cnt    <= MUL_LATENCY;
                    state_after_mul <= HORNER2_ACC;
                    state           <= MUL_WAIT;
                end

                HORNER2_ACC: begin
                    poly_reg  <= COEF_C3 + mul_shr;
                    mul_a_reg <= x2_q;
                    mul_b_reg <= COEF_C3 + mul_shr;
                    state     <= HORNER1_MUL;
                end

                HORNER1_MUL: begin
                    mul_en          <= 1'b1;
                    mul_wait_cnt    <= MUL_LATENCY;
                    state_after_mul <= HORNER1_ACC;
                    state           <= MUL_WAIT;
                end

                HORNER1_ACC: begin
                    poly_reg  <= COEF_C1 + mul_shr;
                    mul_a_reg <= x_q;
                    mul_b_reg <= COEF_C1 + mul_shr;
                    state     <= FINAL_MUL;
                end

                FINAL_MUL: begin
                    mul_en          <= 1'b1;
                    mul_wait_cnt    <= MUL_LATENCY;
                    state_after_mul <= FINAL_PIPE;
                    state           <= MUL_WAIT;
                end

                FINAL_PIPE: begin
                    sin_q <= mul_shr;
                    state <= SCALE_LOAD;
                end

                SCALE_LOAD: begin
                    mul_a_reg <= sign_flag ? -sin_q : sin_q;
                    mul_b_reg <= 32'sd10000;
                    state     <= SCALE_EXEC;
                end

                SCALE_EXEC: begin
                    mul_en          <= 1'b1;
                    mul_wait_cnt    <= MUL_LATENCY;
                    state_after_mul <= SCALE_SAVE;
                    state           <= MUL_WAIT;
                end

                SCALE_SAVE: begin
                    scale_prod <= mul_pipe;
                    state      <= SCALE_ROUND;
                end

                SCALE_ROUND: begin
                    scale_round <= (scale_prod >= 0) ? (scale_prod + ROUND_CONST)
                                                     : (scale_prod - ROUND_CONST);
                    state <= SCALE_OUT;
                end

                SCALE_OUT: begin
                    milli_val = scale_round >>> QSHIFT;
                    if      (milli_val >  32'sd32767) result <= 16'sd32767;
                    else if (milli_val < -32'sd32768) result <= -16'sd32768;
                    else                              result <= milli_val[`INPUTOUTBIT-1:0];
                    done  <= 1'b1;
                    state <= IDLE;
                end

                MUL_WAIT: begin
                    if (mul_wait_cnt <= 1) begin
                        mul_wait_cnt <= 0;
                        state        <= state_after_mul;
                    end else begin
                        mul_wait_cnt <= mul_wait_cnt - 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule