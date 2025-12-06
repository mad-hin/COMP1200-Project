//`define INPUTOUTBIT 32

// 要求
// 输入：整数，-999至999，角度制
// 输出格式：十进制，带符号，科学计数法，八位有效数字
// module里的注释用英文
// 不可以用IP和LUT
// 只要不是直接查表输出答案就不算用LUT
// 用霍纳多项式算法似乎能做到（有bug），git-69d1e046be72fa7ad36474690a8befeaf5be5a8b
// 现在在尝试CORDIC算法


`timescale 1ns / 1ps
`include "define.vh"

(* keep_hierarchy = "no" *)
module sin(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,
    output reg  signed [`INPUTOUTBIT-1:0] result, // Q24.8
    output reg  done
);
    // Fixed-point and iteration settings
    localparam integer QSHIFT     = 8;      // Q24.8 fractional bits
    localparam integer ITERATIONS = 12;     // CORDIC iterations

    // CORDIC angle table: atan(2^-i) in degree (Q8). Algorithm constants (not function LUT).
    reg signed [31:0] ATAN_TABLE [0:11];
    initial begin
        ATAN_TABLE[0]  = 32'sd11520;  // 45.000° * 256
        ATAN_TABLE[1]  = 32'sd6801;   // 26.565°
        ATAN_TABLE[2]  = 32'sd3593;   // 14.036°
        ATAN_TABLE[3]  = 32'sd1824;   // 7.125°
        ATAN_TABLE[4]  = 32'sd915;    // 3.576°
        ATAN_TABLE[5]  = 32'sd458;    // 1.789°
        ATAN_TABLE[6]  = 32'sd229;    // 0.895°
        ATAN_TABLE[7]  = 32'sd114;    // 0.448°
        ATAN_TABLE[8]  = 32'sd57;     // 0.224°
        ATAN_TABLE[9]  = 32'sd29;     // 0.112°
        ATAN_TABLE[10] = 32'sd14;     // 0.056°
        ATAN_TABLE[11] = 32'sd7;      // 0.028°
    end

    // CORDIC gain K ≈ 0.607252935 -> Q8 ≈ 155
    localparam signed [31:0] CORDIC_GAIN = 32'sd155;

    // Degree constants
    localparam signed [15:0] DEG_180 = 16'sd180;
    localparam signed [15:0] DEG_360 = 16'sd360;
    localparam signed [15:0] DEG_90  = 16'sd90;

    // FSM states
    localparam [3:0]
        IDLE          = 4'd0,
        PRE_NORM_CMP  = 4'd1, // compare & candidates
        INIT          = 4'd2,
        ITER_SHIFT    = 4'd3, // shift-only + fetch atan
        ITER_ADD      = 4'd4, // add/sub with latched operands
        SCALE_EXTEND  = 4'd5, // sign-extend only
        SCALE_NEGATE  = 4'd6, // negate if needed
        OUTPUT        = 4'd7,
        PRE_NORM_SEL  = 4'd8; // select normalized angle

    reg [3:0] state;
    reg [3:0] iter_cnt;

    // Input and quadrant handling
    reg signed [15:0] a16_q;                 // 16-bit latched input
    reg               sign_flag;             // final sign
    reg signed [15:0] angle_norm, angle_work;// normalized angle and first-quadrant angle

    // Pre-normalization pipeline regs (to split compare/add from selection)
    reg               a_gt180, a_lt180;
    reg signed [15:0] a_sub360, a_add360;

    // Data path: x/y use 24-bit Q8 to shorten CARRY chains; z uses 18-bit Q8 (covers ±180*256)
    reg signed [23:0] x, y;
    reg signed [17:0] z;

    // Two-cycle pipeline temporaries
    reg signed [23:0] x_shift, y_shift;      // shifted values
    reg signed [17:0] atan_d;                // fetched atan constant (Q8)
    reg               z_ge0;                 // latched sign of z (z >= 0)

    // Intermediate register for sign extension
    reg signed [31:0] y_extended;

    // Main sequential logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            iter_cnt   <= 4'd0;
            a16_q      <= 16'sd0;
            sign_flag  <= 1'b0;
            angle_norm <= 16'sd0;
            angle_work <= 16'sd0;

            a_gt180    <= 1'b0;
            a_lt180    <= 1'b0;
            a_sub360   <= 16'sd0;
            a_add360   <= 16'sd0;

            x <= 24'sd0; y <= 24'sd0;
            z <= 18'sd0;
            x_shift <= 24'sd0; y_shift <= 24'sd0;
            atan_d  <= 18'sd0;
            z_ge0   <= 1'b0;

            y_extended <= 32'sd0;
            result <= 32'sd0;
            done   <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        // Latch and truncate input to 16-bit to reduce comparator/adder width
                        a16_q <= $signed(a[15:0]);
                        state <= PRE_NORM_CMP;
                    end
                end

                PRE_NORM_CMP: begin
                    // Cycle 1: compute compares and candidate results (all locally registered)
                    a_gt180  <= (a16_q >  DEG_180);
                    a_lt180  <= (a16_q < -DEG_180);
                    a_sub360 <= a16_q - DEG_360;
                    a_add360 <= a16_q + DEG_360;
                    state    <= PRE_NORM_SEL;
                end

                PRE_NORM_SEL: begin
                    // Cycle 2: select normalized angle (short combinational path)
                    if      (a_gt180) angle_norm <= a_sub360;
                    else if (a_lt180) angle_norm <= a_add360;
                    else              angle_norm <= a16_q;
                    state <= INIT;
                end

                INIT: begin
                    // Map to first quadrant and record sign
                    sign_flag  <= (angle_norm < 0);
                    angle_work <= angle_norm[15] ? -angle_norm : angle_norm;
                    if (angle_work > DEG_90) angle_work <= (DEG_180 - angle_work);

                    // Initialize vector and angle in Q8
                    // x0 = K<<Q (Q8), y0 = 0; z0 = angle<<Q (Q8, kept in 18-bit)
                    x <= $signed(CORDIC_GAIN) <<< QSHIFT; // 155<<8 = 39680 fits 24-bit
                    y <= 24'sd0;
                    z <= $signed({1'b0, angle_work}) <<< QSHIFT; // zero-extend then shift
                    iter_cnt <= 4'd0;
                    state    <= ITER_SHIFT;
                end

                ITER_SHIFT: begin
                    if (iter_cnt < ITERATIONS) begin
                        // Cycle 1: shifts only + fetch atan constant; also latch z sign
                        x_shift <= $signed(y) >>> iter_cnt;
                        y_shift <= $signed(x) >>> iter_cnt;
                        atan_d  <= $signed(ATAN_TABLE[iter_cnt][17:0]); // Q8 constant
                        z_ge0   <= ~z[17]; // z >= 0 if MSB is 0
                        state   <= ITER_ADD;
                    end else begin
                        state <= SCALE_EXTEND;
                    end
                end

                ITER_ADD: begin
                    // Cycle 2: add/sub with previously latched operands/constants
                    if (z_ge0) begin
                        x <= x - x_shift;
                        y <= y + y_shift;
                        z <= z - atan_d;
                    end else begin
                        x <= x + x_shift;
                        y <= y - y_shift;
                        z <= z + atan_d;
                    end
                    iter_cnt <= iter_cnt + 1'b1;
                    state    <= ITER_SHIFT;
                end

                SCALE_EXTEND: begin
                    // Cycle 1: Only sign-extend 24->32 (no arithmetic)
                    y_extended <= $signed({{8{y[23]}}, y});
                    state <= SCALE_NEGATE;
                end

                SCALE_NEGATE: begin
                    // Cycle 2: Apply negation if needed (short path)
                    if (sign_flag)
                        result <= -y_extended;
                    else
                        result <= y_extended;
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    done  <= 1'b1;   // one-cycle valid strobe
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule