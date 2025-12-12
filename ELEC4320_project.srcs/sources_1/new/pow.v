`timescale 1ns / 1ps
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
    input wire signed [31:0] a,
    input wire signed [31:0] b,
    output reg signed [31:0] result,
    output reg error,
    output reg done
);

    // ... (Constants and Params same as before) ...
    localparam signed [31:0] LN2_FIXED    = 32'h0000_B172; 
    localparam signed [31:0] RECIP_LN2    = 32'h0001_7154; 
    localparam signed [31:0] CORDIC_K     = 32'h0001_3521; 
    localparam ITERATIONS = 16;

    // States
    localparam S_IDLE         = 0;
    localparam S_VALIDATE     = 1; 
    localparam S_PREP_LN      = 2;
    localparam S_CALC_LN      = 3;
    localparam S_MULT         = 4; 
    localparam S_REDUCE_1     = 5;
    localparam S_REDUCE_2     = 6;
    localparam S_CALC_EXP     = 7;
    localparam S_CONVERT_PREP = 8;
    localparam S_CONVERT      = 9; 
    localparam S_DONE         = 10;

    reg [3:0] state;

    reg signed [31:0] x, y, z;
    reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i;
    reg repeat_done;
    reg signed [31:0] abs_a;
    reg result_is_neg;
    reg signed [31:0] ln_a_val;
    reg signed [63:0] mult_product; 
    reg signed [31:0] k_integer;
    reg signed [31:0] current_input;
    reg [5:0] shift_count;
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [31:0] e_ln2;
    reg [31:0] ieee_comb; 
    
    // IEEE Exponent Calc variable
    reg signed [31:0] calc_exp; 

    // ATANH ROM
    reg signed [31:0] atanh_val;
    
    reg signed [63:0] temp_k; 
    reg signed [31:0] k_times_ln2;
    
    always @(*) begin
        case(i)
            1: atanh_val = 32'h0000_8C9F;
            2: atanh_val = 32'h0000_4162;
            3: atanh_val = 32'h0000_202B;
            4: atanh_val = 32'h0000_1005;
            5: atanh_val = 32'h0000_0800;
            6: atanh_val = 32'h0000_0400;
            7: atanh_val = 32'h0000_0200;
            8: atanh_val = 32'h0000_0100;
            9: atanh_val = 32'h0000_0080;
            10: atanh_val = 32'h0000_0040;
            11: atanh_val = 32'h0000_0020;
            12: atanh_val = 32'h0000_0010;
            13: atanh_val = 32'h0000_0008;
            14: atanh_val = 32'h0000_0004;
            15: atanh_val = 32'h0000_0002;
            16: atanh_val = 32'h0000_0001;
            default: atanh_val = 0;
        endcase
    end

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

                // ============================================================
                // 1. ERROR CHECK: INPUT RANGE
                // ============================================================
                S_VALIDATE: begin
                    if (a == 0) begin
                        if (b <= 0) begin
                            // Error: 0^0 or 0^-n is undefined/infinity
                            error <= 1;
                            result <= 32'h7FC00000; // IEEE NaN
                            state <= S_DONE;
                        end else begin
                            // Valid: 0^n = 0
                            result <= 0;
                            state <= S_DONE;
                        end
                    end else if (a < 0) begin
                        // Negative Base Logic
                        result_is_neg <= b[0]; // Negative if b is odd
                        abs_a <= -a;
                        state <= S_PREP_LN;
                        if (b == 0) begin
                            result <= 1;
                            state <= S_DONE;
                        end
                    end else begin
                        // Positive Base
                        result_is_neg <= 0;
                        abs_a <= a;
                        state <= S_PREP_LN;
                        if (b == 0) begin
                            result <= 1;
                            state <= S_DONE;
                        end
                    end
                end

                S_PREP_LN: begin
                    shift_count = clz(abs_a);
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
                        state <= S_MULT;
                    end
                end
                S_MULT: begin mult_product <= $signed(b) * ln_a_val; state <= S_REDUCE_1; end
                S_REDUCE_1: begin
                    temp_k = mult_product * RECIP_LN2;
                    k_integer <= temp_k >>> 32; state <= S_REDUCE_2;
                end
                S_REDUCE_2: begin
                    k_times_ln2 = k_integer * LN2_FIXED;
                    z <= mult_product[31:0] - k_times_ln2; 
                    x <= CORDIC_K; y <= CORDIC_K; i <= 1; repeat_done <= 0; state <= S_CALC_EXP;
                end
                S_CALC_EXP: begin
                    if (z[31] == 0) begin x_next = x + (y >>> i); y_next = y + (x >>> i); z_next = z - atanh_val; end 
                    else begin x_next = x - (y >>> i); y_next = y - (x >>> i); z_next = z + atanh_val; end
                    x <= x_next; y <= y_next; z <= z_next;
                    if (i <= ITERATIONS) begin
                        if ((i==4||i==13)&&!repeat_done) repeat_done<=1; else begin i<=i+1; repeat_done<=0; end
                    end else begin state <= S_CONVERT_PREP; end
                end
                S_CONVERT_PREP: begin abs_final <= x[31] ? -x : x; state <= S_CONVERT; end

                // ============================================================
                // 2. ERROR CHECK: OVERFLOW
                // ============================================================
                S_CONVERT: begin
                    if (abs_final == 0) begin
                        ieee_comb = 0;
                    end else begin
                        norm_shift = clz(abs_final);
                        
                        // Calculate Exponent: 127 + 15 - norm + k
                        calc_exp = 142 - norm_shift + k_integer;

                        // Check Overflow / Underflow
                        if (calc_exp >= 255) begin
                            // OVERFLOW: Return Infinity and set Error
                            error <= 1;
                            ieee_comb = {result_is_neg, 8'hFF, 23'h0}; // Infinity
                        end else if (calc_exp <= 0) begin
                            // UNDERFLOW: Return 0 (Not an error, just small)
                            ieee_comb = 0;
                        end else begin
                            // VALID
                            ieee_comb[31] = result_is_neg;
                            ieee_comb[30:23] = calc_exp[7:0]; 
                            ieee_comb[22:0]  = (abs_final << norm_shift) >> 8;
                        end
                    end
                    
                    result <= ieee_comb;
                    state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule