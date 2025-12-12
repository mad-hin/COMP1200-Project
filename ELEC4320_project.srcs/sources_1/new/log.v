`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 16:05:32
// Design Name: 
// Module Name: log
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
module log (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [31:0] a,   
    input  wire signed [31:0] b,      
    output reg  signed [31:0] result, 
    output reg  error,
    output reg  done
);

    localparam signed [31:0] ln2_fixed_point=32'h0000_B172; 
    localparam ITERATIONS=16;

    reg [3:0] state;
    localparam S_IDLE=0;
    localparam S_VALIDATE=1;
    localparam S_PREP_B=2;
    localparam S_CALC_B=3;
    localparam S_PREP_BASE=4;
    localparam S_CALC_BASE=5;
    localparam S_DIVIDE=6;
    localparam S_CONVERT=7;
    localparam S_DONE=8;

    // Internal Signals
    reg signed [31:0] x, y, z;
    reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i; 
    reg repeat_done; 
    
    reg signed [31:0] ln_b_val;
    reg signed [31:0] ln_base_val;
    reg signed [31:0] final_fixed; 
    
    reg signed [31:0] current_input;
    reg [5:0] shift_count; 

    // Table size 1-16
    reg signed [31:0] atanh_table [0:17]; 
    
    initial begin
        // atanh(0.5)
        atanh_table[1]=32'h0000_8C9F; 
        // atanh(0.25)
        atanh_table[2]=32'h0000_4162; 
        atanh_table[3]=32'h0000_202B; 
        atanh_table[4]=32'h0000_1005; 
        atanh_table[5]=32'h0000_0800; 
        atanh_table[6]=32'h0000_0400;
        atanh_table[7]=32'h0000_0200;
        atanh_table[8]=32'h0000_0100;
        atanh_table[9]=32'h0000_0080;
        atanh_table[10]=32'h0000_0040;
        atanh_table[11]=32'h0000_0020;
        atanh_table[12]=32'h0000_0010;
        atanh_table[13]=32'h0000_0008;
        atanh_table[14]=32'h0000_0004;
        atanh_table[15]=32'h0000_0002;
        atanh_table[16]=32'h0000_0001;
    end

    // Helper function: Leading Zero Count
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

    // IEEE Signals
    reg [31:0] ieee_out;
    reg [7:0]  exp;
    reg [22:0] mant;
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [63:0] numerator_64;
    reg signed [31:0] e_ln2;
    
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            result <= 0;
            error <= 0;
            done <= 0;
            i <= 1;
            repeat_done <= 0;
            x <= 0; y <= 0; z <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    error <= 0;
                    if (start) state <= S_VALIDATE;
                end

                S_VALIDATE: begin
                    if (b <= 0 || a <= 0 || a == 1) begin
                        error <= 1;
                        state <= S_DONE;
                    end else begin
                        state <= S_PREP_B;
                    end
                end

                S_PREP_B: begin
                    shift_count = clz(b); 
                    current_input = ($unsigned(b) << shift_count) >> 16; 
                    
                    x<=current_input+32'h0001_0000;
                    y<=current_input-32'h0001_0000;
                    z<=(32-shift_count)*ln2_fixed_point;
                    
                    i<=1;
                    repeat_done<=0;
                    state<=S_CALC_B;
                end

                // ------------------------------------------------
                // CORDIC Core
                // ------------------------------------------------
                S_CALC_B, S_CALC_BASE: begin
                    // 1. CORDIC Equation
                    // Vectoring Mode: Drive y to 0.
                    // If y > 0, rotate DOWN (subtract angle). d = -1.
                    // If y < 0, rotate UP (add angle). d = +1.
                    // z accumulates angle: z_next = z - d*angle.
                    // if y>0 (d=-1): z_next = z - (-angle) = z + angle.
                    // if y<0 (d=+1): z_next = z - (+angle) = z - angle.
                    
                    // WAIT! Mathematical Identity Check:
                    // We want z to store 0.5 * ln((x+y)/(x-y)).
                    // Standard CORDIC accumulation:
                    // If we use d = sign(x)*sign(y), then z accumulates correctly?
                    // Let's stick to the standard implementation that matches the table values:
                    // If y < 0, we add Y term to X, and SUBTRACT angle from Z.
                    
                    // FIX: Reverting to standard hyperbolic vectoring signs
                    if ((y[31] == 0)) begin // y > 0 (Positive)
                        x_next = x - (y >>> i);
                        y_next = y - (x >>> i);
                        z_next = z + atanh_table[i]; 
                    end else begin // y < 0 (Negative)
                        x_next = x + (y >>> i);
                        y_next = y + (x >>> i);
                        z_next = z - atanh_table[i];
                    end
                    
                    x <= x_next;
                    y <= y_next;
                    z <= z_next;

                    // 2. Iteration Control
                    if (i <= ITERATIONS) begin
                        if ((i == 4 || i == 13) && repeat_done == 0) begin
                            repeat_done <= 1; 
                        end else begin
                            i <= i + 1;
                            repeat_done <= 0; 
                        end
                    end else begin
                        // 3. Final Calculation
                        // Math: ln(Input) = 2 * z_accum - Initial_E_offset

                        if (state == S_CALC_B) 
                            e_ln2 = (32 - clz(b))*ln2_fixed_point;
                        else 
                            e_ln2 = (32 - clz(a))*ln2_fixed_point;

                        if (state == S_CALC_B) begin
                             ln_b_val <= (z <<< 1) - e_ln2; 
                             state <= S_PREP_BASE;
                        end else begin
                             ln_base_val <= (z <<< 1) - e_ln2;
                             state <= S_DIVIDE;
                        end
                    end
                end

                // ------------------------------------------------
                // Normalize Input Base
                // ------------------------------------------------
                S_PREP_BASE: begin
                     shift_count = clz(a);
                     current_input = ($unsigned(a) << shift_count) >> 16;
                     
                     x <= current_input + 32'h0001_0000; 
                     y <= current_input - 32'h0001_0000; 
                     z <= (32 - shift_count) * ln2_fixed_point; 
                     
                     i <= 1;
                     repeat_done <= 0;
                     state <= S_CALC_BASE;
                end

                // ------------------------------------------------
                // Division
                // ------------------------------------------------
                S_DIVIDE: begin
                    if (ln_base_val == 0) begin
                        final_fixed <= 32'h7FFF_FFFF; 
                    end else begin
                        numerator_64 = ln_b_val; 
                        // Q16.16 Division
                        final_fixed <= (numerator_64 <<< 16) / ln_base_val;
                    end
                    state <= S_CONVERT;
                end

                // ------------------------------------------------
                // IEEE 754 Conversion
                // ------------------------------------------------
                S_CONVERT: begin
                    ieee_out[31] = final_fixed[31]; // Sign
                    abs_final = final_fixed[31] ? -final_fixed : final_fixed;
                    
                    if (abs_final == 0) begin
                        ieee_out = 0;
                    end else begin
                        norm_shift = clz(abs_final);
                        
                        // Exponent: 127 + (31 - norm_shift - 16)
                        exp=142-norm_shift;
                        
                        mant=(abs_final << norm_shift) >> 8; 
                        
                        ieee_out[30:23] = exp;
                        ieee_out[22:0]  = mant;
                    end
                    
                    result <= ieee_out;
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