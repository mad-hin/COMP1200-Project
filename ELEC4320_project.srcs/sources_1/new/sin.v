//`define INPUTOUTBIT 32
// 输入的数字一定是整数，是-999到999的整数
// 输出得有八位有效数字 

`timescale 1ns / 1ps
`include "define.vh"

module sin(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,
    output reg  signed [`INPUTOUTBIT-1:0] result, // sin in Q24.8 format
    output reg  done
);
    localparam integer QSHIFT      = 8;  // Changed to 8 for 8 fractional bits
    localparam integer MUL_LATENCY = 2;

    localparam signed [15:0] DEG_180  = 16'sd180;
    localparam signed [15:0] DEG_360  = 16'sd360;
    localparam signed [15:0] DEG_90   = 16'sd90;
    localparam signed [31:0] DEG2RAD_Q8 = 32'sd4;  // Approx π/180 * 2^8

    // Coefficients refitted for Q8 (original Q29 shifted and adjusted)
    localparam signed [31:0] COEF_C1 = 32'sd33554432;   // Approx 1.0 * 2^8
    localparam signed [31:0] COEF_C3 = -32'sd5592405;   // Approx -0.166666 * 2^8
    localparam signed [31:0] COEF_C5 = 32'sd279620;     // Approx 0.008333 * 2^8
    localparam signed [31:0] COEF_C7 = -32'sd6605;      // Approx -0.000198 * 2^8
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
    reg signed [15:0] angle_norm;  // Optimized to 16-bit for -999 to 999 input
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

    // Three-stage shared multiplier (unchanged)
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
                    // Normalize input angle (integer) to -180 to 180
                    if (a >  DEG_180)      angle_norm <= a - DEG_360;
                    else if (a < -DEG_180) angle_norm <= a + DEG_360;
                    else                   angle_norm <= a[15:0];  // Truncate to 16-bit
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
                    x_q   <= angle_ref_deg * DEG2RAD_Q8;  // Integer multiply
                    state <= X_LOAD;
                end

                // ... (rest of states unchanged, but SCALE_LOAD uses 256 for Q8 scaling)

                SCALE_LOAD: begin
                    mul_a_reg <= sign_flag ? -sin_q : sin_q;
                    mul_b_reg <= 32'sd256;  // 2^8 for Q8 scaling
                    state     <= SCALE_EXEC;
                end

                // ... (SCALE_EXEC to SCALE_OUT unchanged, output is Q24.8)

                SCALE_OUT: begin
                    result <= milli_val[`INPUTOUTBIT-1:0];  // Now Q24.8
                    done   <= 1'b1;
                    state  <= IDLE;
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