`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 16:06:43
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
    output reg signed [`INPUTOUTBIT-1:0] result, // 32 bit IEEE754
    output reg error = 0,
    output reg done
);

    localparam signed [31:0] ln2_fixed_point = 32'h0000_B172;
    localparam signed [31:0] e_fixed_point = 32'h0002_B7E1;  // e in fixed point
    localparam ITERATIONS = 16;

    reg [3:0] state;
    localparam S_IDLE = 0;
    localparam S_VALIDATE = 1;
    localparam S_CALC_LN_A = 2;
    localparam S_MULTIPLY = 3;
    localparam S_CALC_EXP = 4;
    localparam S_CONVERT = 5;
    localparam S_DONE = 6;

    // Internal Signals
    reg signed [31:0] x, y, z;
    reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i;
    reg repeat_done;
    
    reg signed [31:0] ln_a_val;
    reg signed [31:0] b_times_ln_a;
    reg signed [31:0] current_input;
    reg [5:0] shift_count;

    // atanh table for CORDIC hyperbolic mode
    reg signed [31:0] atanh_table [0:17];
    
    initial begin
        atanh_table[1] = 32'h0000_8C9F;
        atanh_table[2] = 32'h0000_4162;
        atanh_table[3] = 32'h0000_202B;
        atanh_table[4] = 32'h0000_1005;
        atanh_table[5] = 32'h0000_0800;
        atanh_table[6] = 32'h0000_0400;
        atanh_table[7] = 32'h0000_0200;
        atanh_table[8] = 32'h0000_0100;
        atanh_table[9] = 32'h0000_0080;
        atanh_table[10] = 32'h0000_0040;
        atanh_table[11] = 32'h0000_0020;
        atanh_table[12] = 32'h0000_0010;
        atanh_table[13] = 32'h0000_0008;
        atanh_table[14] = 32'h0000_0004;
        atanh_table[15] = 32'h0000_0002;
        atanh_table[16] = 32'h0000_0001;
    end

    // Leading Zero Count helper function
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

    // IEEE 754 Conversion signals
    reg [31:0] ieee_out;
    reg [7:0] exp;
    reg [22:0] mant;
    reg [31:0] abs_final;
    reg [5:0] norm_shift;
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
                    // Check for invalid cases: a <= 0
                    if (a <= 0) begin
                        error <= 1;
                        state <= S_DONE;
                    end else begin
                        state <= S_CALC_LN_A;
                    end
                end

                // ------------------------------------------------
                // Calculate ln(a) using CORDIC
                // ------------------------------------------------
                S_CALC_LN_A: begin
                    shift_count = clz(a);
                    current_input = ($unsigned(a) << shift_count) >> 16;
                    
                    x <= current_input + 32'h0001_0000;
                    y <= current_input - 32'h0001_0000;
                    z <= (32 - shift_count) * ln2_fixed_point;
                    
                    i <= 1;
                    repeat_done <= 0;
                    state <= S_CALC_LN_A;  // Will iterate and transition
                end

                // CORDIC Iteration for ln(a)
                S_CALC_LN_A: begin
                    if (i <= ITERATIONS) begin
                        if ((y[31] == 0)) begin // y > 0
                            x_next = x - (y >>> i);
                            y_next = y - (x >>> i);
                            z_next = z + atanh_table[i];
                        end else begin // y < 0
                            x_next = x + (y >>> i);
                            y_next = y + (x >>> i);
                            z_next = z - atanh_table[i];
                        end
                        
                        x <= x_next;
                        y <= y_next;
                        z <= z_next;

                        if ((i == 4 || i == 13) && repeat_done == 0) begin
                            repeat_done <= 1;
                        end else begin
                            i <= i + 1;
                            repeat_done <= 0;
                        end
                    end else begin
                        // Calculate ln(a)
                        e_ln2 = (32 - clz(a)) * ln2_fixed_point;
                        ln_a_val <= (z <<< 1) - e_ln2;
                        state <= S_MULTIPLY;
                    end
                end

                // ------------------------------------------------
                // Multiply b * ln(a)
                // ------------------------------------------------
                S_MULTIPLY: begin
                    // Q16.16 multiplication
                    numerator_64 = ($signed(b) * ln_a_val) >>> 16;
                    b_times_ln_a <= numerator_64[31:0];
                    
                    // Prepare for exponential calculation
                    shift_count = clz(b_times_ln_a);
                    current_input = ($unsigned(b_times_ln_a) << shift_count) >> 16;
                    
                    x <= e_fixed_point;
                    y <= 32'h0000_0000;
                    z <= b_times_ln_a;
                    
                    i <= 1;
                    repeat_done <= 0;
                    state <= S_CALC_EXP;
                end

                // ------------------------------------------------
                // Calculate exp(b*ln(a)) using CORDIC rotation mode
                // ------------------------------------------------
                S_CALC_EXP: begin
                    if (i <= ITERATIONS) begin
                        // Rotation mode: drive z to 0
                        if (z[31] == 0) begin // z > 0, rotate counterclockwise
                            x_next = x - (y >>> i);
                            y_next = y + (x >>> i);
                            z_next = z - atanh_table[i];
                        end else begin // z < 0, rotate clockwise
                            x_next = x + (y >>> i);
                            y_next = y - (x >>> i);
                            z_next = z + atanh_table[i];
                        end
                        
                        x <= x_next;
                        y <= y_next;
                        z <= z_next;

                        if ((i == 4 || i == 13) && repeat_done == 0) begin
                            repeat_done <= 1;
                        end else begin
                            i <= i + 1;
                            repeat_done <= 0;
                        end
                    end else begin
                        // Result is in x register
                        state <= S_CONVERT;
                    end
                end

                // ------------------------------------------------
                // IEEE 754 Conversion
                // ------------------------------------------------
                S_CONVERT: begin
                    ieee_out[31] = x[31];  // Sign
                    abs_final = x[31] ? -x : x;
                    
                    if (abs_final == 0) begin
                        ieee_out = 0;
                    end else begin
                        norm_shift = clz(abs_final);
                        exp = 142 - norm_shift;  // 127 + 15 bias adjustment
                        mant = (abs_final << norm_shift) >> 8;
                        
                        ieee_out[30:23] = exp;
                        ieee_out[22:0] = mant;
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
