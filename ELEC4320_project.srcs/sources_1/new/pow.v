`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 21:35:12
// Design Name: 
// Module Name: pow
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
module pow(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a,
    input wire signed [`INPUTOUTBIT-1:0] b,
    output reg [`INPUTOUTBIT-1:0] result, // BF16
    output reg error,
    output reg done
);

    // ==========================================
    // Constants
    // ==========================================
    localparam signed [31:0] LN2_FIXED=32'h0000_B172; 
    localparam signed [31:0] RECIP_LN2=32'h0001_7154; 
    localparam signed [31:0] CORDIC_K=32'h0001_3521; 
    localparam ITERATIONS=16;

    // ==========================================
    // Pipelined FSM States
    // ==========================================
    reg [4:0] state; // Expanded to 5 bits for more states
    
    localparam S_IDLE=0;
    localparam S_VALIDATE=1;
    localparam S_PREP_LN_CLZ=2; 
    localparam S_PREP_LN_SHIFT=3;
    localparam S_CALC_LN=4;
    localparam S_MULT_1=5; 
    localparam S_MULT_2=6; 
    localparam S_REDUCE_K_1=7;
    localparam S_REDUCE_K_2=8;
    localparam S_REDUCE_R_1=9;
    localparam S_REDUCE_R_2=10;
    localparam S_CALC_EXP=11;
    localparam S_CONVERT_CLZ=12; 
    localparam S_CONVERT_SHIFT=13;
    localparam S_CONVERT_PACK=14; 
    localparam S_DONE=15;

    // ==========================================
    // Internal Signals
    // ==========================================
    reg signed [31:0] x, y, z;
    reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i;
    reg repeat_done;
    reg signed [31:0] abs_a;
    reg result_is_neg;
    reg signed [31:0] ln_a_val;
    reg signed [31:0] b_extended;
    
    // Pipelined Multiplier Registers
    reg signed [31:0] mult_op_a, mult_op_b;
    reg signed [63:0] mult_result; 
    
    reg signed [31:0] k_integer;
    reg signed [31:0] current_input;
    reg [5:0] shift_count;
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [31:0] e_ln2;

    // BF16 output register
    reg [15:0] result_reg;

    reg signed [31:0] calc_exp; 
    reg signed [63:0] temp_mult;
    reg signed [63:0] temp_kln2;

    // 7-bit mantissa for BF16
    reg [6:0] bf16_mant;

    // ATANH ROM (same values for CORDIC hyperbolic)
    reg signed [31:0] atanh_val;
    always @(*) begin
        case(i)
            1:  atanh_val=32'h0000_8C9F;
            2:  atanh_val=32'h0000_4162;
            3:  atanh_val=32'h0000_202B;
            4:  atanh_val=32'h0000_1005;
            5:  atanh_val=32'h0000_0800;
            6:  atanh_val=32'h0000_0400;
            7:  atanh_val=32'h0000_0200;
            8:  atanh_val=32'h0000_0100;
            9:  atanh_val=32'h0000_0080;
            10: atanh_val=32'h0000_0040;
            11: atanh_val=32'h0000_0020;
            12: atanh_val=32'h0000_0010;
            13: atanh_val=32'h0000_0008;
            14: atanh_val=32'h0000_0004;
            15: atanh_val=32'h0000_0002;
            16: atanh_val=32'h0000_0001;
            default: atanh_val=0;
        endcase
    end

    // CLZ Function
    function [5:0] clz;
        input [31:0] in_val;
        integer k;
        begin
            clz = 0;
            begin : clz_loop
                for (k = 31; k >= 0; k = k - 1) begin
                    if (in_val[k]) disable clz_loop;
                    clz = clz + 1;
                end
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            result <= 0;
            error <= 0;
            done <= 0;
            i <= 1;
            x <= 0; y <= 0; z <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    error <= 0;
                    if (start) state <= S_VALIDATE;
                end

                S_VALIDATE: begin
                    b_extended<={{16{b[15]}}, b};
                    if (a == 0) begin
                        if (b <= 0) begin
                            error<=1; 
                            state<=S_DONE;
                        end else begin
                            result_reg<=0; 
                            state<=S_DONE;
                        end
                    end else if (b == 0) begin
                            result_reg<=16'h3f80; 
                            state<=S_DONE;
                        end else if (a[15]) begin
                            result_is_neg<=b[0]; 
                            // Zero-extend absolute value
                            abs_a<={{16{1'b0}}, -a};
                            state<=S_PREP_LN_CLZ; // Go to new CLZ state
                        end else begin
                            result_is_neg<=0;
                            // Zero-extend positive value
                            abs_a<={{16{1'b0}}, a};
                            state<=S_PREP_LN_CLZ; // Go to new CLZ state
                        end
                end

                // ------------------------------------------------
                // 1. Logarithm Prep (Split into 2 cycles)
                // ------------------------------------------------
                S_PREP_LN_CLZ: begin
                    shift_count<=clz(abs_a);
                    state<=S_PREP_LN_SHIFT;
                end

                S_PREP_LN_SHIFT: begin
                    current_input = ($unsigned(abs_a) << shift_count) >> 16;
                    x <= current_input + 32'h0001_0000;
                    y <= current_input - 32'h0001_0000;
                    z <= (32 - shift_count) * LN2_FIXED;
                    i <= 1; 
                    repeat_done <= 0; 
                    state <= S_CALC_LN;
                end

                // LOGARITHM CORDIC - ONE ITERATION PER CLOCK CYCLE
                S_CALC_LN: begin
                    // Pipeline: compute next iteration values in registers
                    if (y[31] == 0) begin 
                        x <= x - (y >>> i); 
                        y <= y - (x >>> i); 
                        z <= z + atanh_val; 
                    end else begin 
                        x <= x + (y >>> i); 
                        y <= y + (x >>> i); 
                        z <= z - atanh_val; 
                    end

                    if ((i == 4 || i == 13) && !repeat_done) begin
                        repeat_done <= 1; 
                    end else if (i < ITERATIONS) begin
                        i <= i + 1; 
                        repeat_done <= 0; 
                    end else begin
                        e_ln2 = (32 - clz(abs_a)) * LN2_FIXED;
                        ln_a_val <= (z <<< 1) - e_ln2;
                        state <= S_MULT_1;
                    end
                end

                // ------------------------------------------------
                // 2. Multiply: P = b * ln(a) (Split)
                // ------------------------------------------------
                S_MULT_1: begin
                    // Cycle 1: Load pipeline registers
                    mult_op_a <= b_extended;
                    mult_op_b <= ln_a_val;
                    state <= S_MULT_2;
                end

                S_MULT_2: begin
                    // Cycle 2: Execute Multiplication
                    // Because inputs are registered, this path starts at Clk edge and ends at Setup.
                    // This creates a clean path for the DSP blocks.
                    mult_result <= mult_op_a * mult_op_b;
                    state <= S_REDUCE_K_1;
                end

                // ------------------------------------------------
                // 3. Range Reduction K (Split)
                // ------------------------------------------------
                S_REDUCE_K_1: begin
                    mult_op_a <= mult_result[31:0];
                    mult_op_b <= RECIP_LN2;
                    state <= S_REDUCE_K_2;
                end

                S_REDUCE_K_2: begin
                    temp_mult = mult_op_a * mult_op_b;
                    k_integer <= temp_mult >>> 32;
                    state <= S_REDUCE_R_1;
                end

                // ------------------------------------------------
                // 4. Range Reduction R (Split)
                // ------------------------------------------------
                S_REDUCE_R_1: begin
                    mult_op_a <= k_integer;
                    mult_op_b <= LN2_FIXED;
                    state <= S_REDUCE_R_2;
                end

                S_REDUCE_R_2: begin
                    temp_kln2 = mult_op_a * mult_op_b;
                    z <= mult_result[31:0] - temp_kln2[31:0]; 
                    x <= CORDIC_K; 
                    y <= CORDIC_K; 
                    i <= 1; 
                    repeat_done <= 0; 
                    state <= S_CALC_EXP;
                end

                // EXPONENTIAL CORDIC - ONE ITERATION PER CLOCK CYCLE
                S_CALC_EXP: begin
                    // Pipeline: compute next iteration values in registers
                    if (z[31] == 0) begin 
                        x <= x + (y >>> i); 
                        y <= y + (x >>> i); 
                        z <= z - atanh_val; 
                    end else begin 
                        x <= x - (y >>> i); 
                        y <= y - (x >>> i); 
                        z <= z + atanh_val; 
                    end
                    
                    if ((i == 4 || i == 13) && !repeat_done) begin
                        repeat_done <= 1; 
                    end else if (i < ITERATIONS) begin
                        i <= i + 1; 
                        repeat_done <= 0; 
                    end else begin 
                        state <= S_CONVERT_CLZ;
                    end
                end

                // ------------------------------------------------
                // 6. Output Conversion (Split)
                // ------------------------------------------------
                S_CONVERT_CLZ: begin
                    // Use only x (not x+y) to avoid doubling
                    abs_final <= x[31] ? -x : x;
                    state <= S_CONVERT_SHIFT;
                end

                S_CONVERT_SHIFT: begin
                    if (abs_final == 0) begin
                        result_reg = 0;
                        state <= S_CONVERT_PACK;
                    end else begin
                        norm_shift <= clz(abs_final);
                        state <= S_CONVERT_PACK;
                    end
                end

                S_CONVERT_PACK: begin
                    if (abs_final == 0) begin
                        result_reg = 0;
                    end else begin
                        // BF16 Exponent: bias(127) + internal_offset - norm_shift + k
                        calc_exp = 142 - norm_shift + k_integer;

                        if (calc_exp >= 255) begin
                            error <= 1;
                            result_reg = {result_is_neg, 8'hFF, 7'h0};  // BF16 ±Inf
                        end else if (calc_exp <= 0) begin
                            result_reg = 0;  // Underflow to zero
                        end else begin
                            // Extract 7-bit mantissa for BF16 (shift by 24 instead of 8)
                            bf16_mant = (abs_final << norm_shift) >> 24;
                            result_reg = {result_is_neg, calc_exp[7:0], bf16_mant};
                        end
                    end
                    state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1;
                    result <= result_reg;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule