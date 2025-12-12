`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/13 02:18:23
// Design Name: 
// Module Name: muti
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
module math_unit(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [1:0] mode,       // 00: Pow(a^b), 01: Exp(e^a), 10: Sqrt(a)
    input wire signed [31:0] a,  // Input 1
    input wire signed [31:0] b,  // Input 2 (Exponent for Pow)
    output reg signed [31:0] result,
    output reg error,
    output reg done
);

    // ==========================================
    // Constants
    // ==========================================
    localparam signed [31:0] LN2_FIXED    = 32'h0000_B172; 
    localparam signed [31:0] RECIP_LN2    = 32'h0001_7154; 
    localparam signed [31:0] CORDIC_K     = 32'h0001_3521; 
    localparam ITERATIONS = 16;

    // ==========================================
    // FSM States
    // ==========================================
    reg [4:0] state;
    
    localparam S_IDLE           = 0;
    localparam S_VALIDATE       = 1;
    
    // LOGARITHM (For Pow)
    localparam S_PREP_LN_CLZ    = 2; 
    localparam S_PREP_LN_SHIFT  = 3;
    localparam S_CALC_LN        = 4;
    
    // MULTIPLIER (For Pow)
    localparam S_MULT_1         = 5; 
    localparam S_MULT_2         = 6; 
    
    // RANGE REDUCTION (For Pow & Exp)
    localparam S_REDUCE_K_1     = 7;
    localparam S_REDUCE_K_2     = 8;
    localparam S_REDUCE_R_1     = 9;
    localparam S_REDUCE_R_2     = 10;
    
    // EXPONENTIAL CORDIC (For Pow & Exp)
    localparam S_CALC_EXP       = 11;
    
    // SQRT (Dedicated States)
    localparam S_SQRT_CALC      = 12;

    // OUTPUT CONVERSION
    localparam S_CONVERT_CLZ    = 13; 
    localparam S_CONVERT_SHIFT  = 14;
    localparam S_CONVERT_PACK   = 15; 
    localparam S_DONE           = 16;

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
    
    reg signed [31:0] mult_op_a, mult_op_b;
    reg signed [63:0] mult_result; // Reused as 'd' for Sqrt
    
    reg signed [31:0] k_integer;
    reg signed [31:0] current_input;
    reg [5:0] shift_count;
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [31:0] e_ln2;
    reg [31:0] ieee_comb; 
    reg signed [31:0] calc_exp; 

    // ATANH ROM
    reg signed [31:0] atanh_val;
    always @(*) begin
        case(i)
            1: atanh_val = 32'h0000_8C9F; 2: atanh_val = 32'h0000_4162; 3: atanh_val = 32'h0000_202B;
            4: atanh_val = 32'h0000_1005; 5: atanh_val = 32'h0000_0800; 6: atanh_val = 32'h0000_0400;
            7: atanh_val = 32'h0000_0200; 8: atanh_val = 32'h0000_0100; 9: atanh_val = 32'h0000_0080;
            10: atanh_val= 32'h0000_0040; 11: atanh_val= 32'h0000_0020; 12: atanh_val= 32'h0000_0010;
            13: atanh_val= 32'h0000_0008; 14: atanh_val= 32'h0000_0004; 15: atanh_val= 32'h0000_0002;
            16: atanh_val= 32'h0000_0001; default: atanh_val = 0;
        endcase
    end

    // Helper: CLZ
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
            result <= 0; error <= 0; done <= 0;
            i <= 1; x <= 0; y <= 0; z <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0; error <= 0;
                    if (start) state <= S_VALIDATE;
                end

                S_VALIDATE: begin
                    // ------------------------------------
                    // MODE 00: POWER (a^b)
                    // ------------------------------------
                    if (mode == 2'b00) begin
                        if (a == 0) begin
                            if (b <= 0) begin error <= 1; result <= 32'h7FC00000; state <= S_DONE; end
                            else begin result <= 0; state <= S_DONE; end
                        end else if (a < 0) begin
                            result_is_neg <= b[0]; abs_a <= -a; state <= S_PREP_LN_CLZ;
                        end else begin
                            result_is_neg <= 0; abs_a <= a; state <= S_PREP_LN_CLZ;
                        end
                    end 
                    // ------------------------------------
                    // MODE 01: EXP (e^a)
                    // ------------------------------------
                    else if (mode == 2'b01) begin
                        result_is_neg <= 0;
                        // Jump directly to Range Reduction
                        // We must setup multiplier to compute k = a * RECIP_LN2
                        // a is integer. To reuse logic, we treat a as Q16.16 (a << 16).
                        state <= S_REDUCE_K_1; 
                    end
                    // ------------------------------------
                    // MODE 10: SQRT (sqrt(a))
                    // ------------------------------------
                    else if (mode == 2'b10) begin
                        if (a < 0) begin
                            error <= 1; result <= 32'h7FC00000; state <= S_DONE;
                        end else if (a == 0) begin
                            result <= 0; state <= S_DONE;
                        end else begin
                            result_is_neg <= 0;
                            // Reuse mult_result as 'd' (Data) and upscale by 32
                            mult_result <= {a, 32'b0};
                            x <= 0; // Reuse x as 'q' (Root)
                            y <= 0; // Reuse y as 'r' (Remainder)
                            i <= 0; // Reuse i as 'count'
                            state <= S_SQRT_CALC;
                        end
                    end
                end

                // ============================================================
                // LOGARITHM STAGE (Only for POW)
                // ============================================================
                S_PREP_LN_CLZ: begin
                    shift_count <= clz(abs_a); state <= S_PREP_LN_SHIFT;
                end
                S_PREP_LN_SHIFT: begin
                    current_input = ($unsigned(abs_a) << shift_count) >> 16;
                    x <= current_input + 32'h0001_0000;
                    y <= current_input - 32'h0001_0000;
                    z <= (32 - shift_count) * LN2_FIXED;
                    i <= 1; repeat_done <= 0; state <= S_CALC_LN;
                end
                S_CALC_LN: begin
                    if (y[31] == 0) begin x_next = x - (y >>> i); y_next = y - (x >>> i); z_next = z + atanh_val; end 
                    else begin x_next = x + (y >>> i); y_next = y + (x >>> i); z_next = z - atanh_val; end
                    x <= x_next; y <= y_next; z <= z_next;
                    if (i <= ITERATIONS) begin
                        if ((i==4||i==13)&&!repeat_done) repeat_done<=1; else begin i<=i+1; repeat_done<=0; end
                    end else begin
                        e_ln2 = (32 - clz(abs_a)) * LN2_FIXED;
                        ln_a_val <= (z <<< 1) - e_ln2;
                        state <= S_MULT_1;
                    end
                end

                // ============================================================
                // MULTIPLIER STAGE (Only for POW)
                // ============================================================
                S_MULT_1: begin
                    mult_op_a <= b; mult_op_b <= ln_a_val; state <= S_MULT_2;
                end
                S_MULT_2: begin
                    mult_result <= mult_op_a * mult_op_b; state <= S_REDUCE_K_1;
                end

                // ============================================================
                // RANGE REDUCTION (Shared by POW and EXP)
                // ============================================================
                S_REDUCE_K_1: begin
                    // If EXP Mode: Input is 'a' (integer). Load as (a << 16).
                    // If POW Mode: Input is mult_result[31:0] (Q16.16).
                    
                    if (mode == 2'b01) mult_op_a <= (a << 16); 
                    else               mult_op_a <= mult_result[31:0];
                    
                    mult_op_b <= RECIP_LN2;
                    state <= S_REDUCE_K_2;
                end
                S_REDUCE_K_2: begin
                    reg signed [63:0] temp_mult;
                    temp_mult = mult_op_a * mult_op_b;
                    k_integer <= temp_mult >>> 32;
                    
                    // Note: For EXP mode, we need to preserve 'a' for the next step.
                    // For POW mode, we need 'mult_result'.
                    // To handle both, we will reload mult_op_a in the next state.
                    state <= S_REDUCE_R_1;
                end
                S_REDUCE_R_1: begin
                    mult_op_a <= k_integer; mult_op_b <= LN2_FIXED; state <= S_REDUCE_R_2;
                end
                S_REDUCE_R_2: begin
                    reg signed [63:0] temp_kln2;
                    temp_kln2 = mult_op_a * mult_op_b; 
                    
                    // Calculate Remainder 'r'
                    if (mode == 2'b01) z <= (a << 16) - temp_kln2[31:0];
                    else               z <= mult_result[31:0] - temp_kln2[31:0];
                    
                    x <= CORDIC_K; y <= CORDIC_K; i <= 1; repeat_done <= 0; state <= S_CALC_EXP;
                end

                // ============================================================
                // EXPONENTIAL CORDIC (Shared)
                // ============================================================
                S_CALC_EXP: begin
                    if (z[31] == 0) begin x_next = x + (y >>> i); y_next = y + (x >>> i); z_next = z - atanh_val; end 
                    else begin x_next = x - (y >>> i); y_next = y - (x >>> i); z_next = z + atanh_val; end
                    x <= x_next; y <= y_next; z <= z_next;
                    if (i <= ITERATIONS) begin
                        if ((i==4||i==13)&&!repeat_done) repeat_done<=1; else begin i<=i+1; repeat_done<=0; end
                    end else begin 
                        state <= S_CONVERT_CLZ;
                    end
                end

                // ============================================================
                // SQUARE ROOT CALCULATION (Dedicated)
                // ============================================================
                S_SQRT_CALC: begin
                    // Registers Reused:
                    // d -> mult_result (64-bit)
                    // q -> x (32-bit)
                    // r -> y (32-bit)
                    // count -> i (5-bit)
                    
                    if (i < 32) begin
                        // r = (r << 2) | ((d >> 62) & 3);
                        y = (y << 2) | ((mult_result >> 62) & 3);
                        mult_result = mult_result << 2;
                        x = x << 1;
                        
                        if (y >= (2 * x + 1)) begin
                            y = y - (2 * x + 1);
                            x = x + 1;
                        end
                        i <= i + 1;
                    end else begin
                        // Set k_integer to -16 for SQRT Mode (Compensation for upscaling)
                        // Because Sqrt(A * 2^32) = Sqrt(A) * 2^16.
                        // We need to subtract 16 from exponent.
                        k_integer <= -16; 
                        state <= S_CONVERT_CLZ;
                    end
                end

                // ============================================================
                // OUTPUT CONVERSION (Shared)
                // ============================================================
                S_CONVERT_CLZ: begin
                    // x holds the final magnitude for all modes
                    abs_final <= x[31] ? -x : x;
                    state <= S_CONVERT_SHIFT;
                end
                S_CONVERT_SHIFT: begin
                    if (abs_final == 0) begin ieee_comb = 0; state <= S_CONVERT_PACK; end
                    else begin norm_shift <= clz(abs_final); state <= S_CONVERT_PACK; end
                end
                S_CONVERT_PACK: begin
                    if (abs_final == 0) begin
                        ieee_comb = 0;
                    end else begin
                        // Common Exponent Logic
                        // 127 + 15 (Fixed Bias) - norm_shift + k_integer
                        calc_exp = 142 - norm_shift + k_integer;

                        if (calc_exp >= 255) begin
                            error <= 1; ieee_comb = {result_is_neg, 8'hFF, 23'h0}; 
                        end else if (calc_exp <= 0) begin
                            ieee_comb = 0;
                        end else begin
                            ieee_comb[31] = result_is_neg;
                            ieee_comb[30:23] = calc_exp[7:0]; 
                            ieee_comb[22:0]  = (abs_final << norm_shift) >> 8;
                        end
                    end
                    result <= ieee_comb; state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1; if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
