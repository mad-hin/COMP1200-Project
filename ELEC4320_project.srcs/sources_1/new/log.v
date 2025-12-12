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

    localparam signed [31:0] ln2_fixed_point = 32'h0000_B172; 
    localparam ITERATIONS = 16;

    reg [4:0] state;
    localparam S_IDLE       = 0;
    localparam S_VALIDATE   = 1;
    localparam S_PREP_B     = 2;
    localparam S_CALC_B     = 3;
    localparam S_PREP_BASE  = 4;
    localparam S_CALC_BASE  = 5;
    localparam S_DIV_PREP   = 6;
    localparam S_DIV_CALC   = 7;
    localparam S_CONVERT    = 8;
    localparam S_DONE       = 9;

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

    // Division Signals
    reg [63:0] div_rem;   
    reg [31:0] div_quo;   
    reg [31:0] div_denom; 
    reg [5:0]  div_cnt;   

    reg signed [31:0] atanh_val;
    
    // Explicit ROM
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

    // Helper: Leading Zero Count
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
    reg [7:0]  ieee_exp;
    reg [22:0] ieee_mant;
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [31:0] e_ln2;
    reg [63:0] rem_shift;
    reg [32:0] sub_res; 
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

                // Normalize B
                S_PREP_B: begin
                    shift_count = clz(b); 
                    current_input = ($unsigned(b) << shift_count) >> 16; 
                    x <= current_input + 32'h0001_0000;
                    y <= current_input - 32'h0001_0000;
                    z <= (32 - shift_count) * ln2_fixed_point;
                    i <= 1;
                    repeat_done <= 0;
                    state <= S_CALC_B;
                end

                // CORDIC Core
                S_CALC_B, S_CALC_BASE: begin
                    if ((y[31] == 0)) begin 
                        x_next = x - (y >>> i);
                        y_next = y - (x >>> i);
                        z_next = z + atanh_val; 
                    end else begin 
                        x_next = x + (y >>> i);
                        y_next = y + (x >>> i);
                        z_next = z - atanh_val;
                    end
                    x <= x_next; y <= y_next; z <= z_next;

                    if (i <= ITERATIONS) begin
                        if ((i == 4 || i == 13) && repeat_done == 0) begin
                            repeat_done <= 1; 
                        end else begin
                            i <= i + 1;
                            repeat_done <= 0; 
                        end
                    end else begin
                        if (state == S_CALC_B) e_ln2 = (32 - clz(b))*ln2_fixed_point;
                        else e_ln2 = (32 - clz(a))*ln2_fixed_point;

                        if (state == S_CALC_B) begin
                             ln_b_val <= (z <<< 1) - e_ln2; 
                             state <= S_PREP_BASE;
                        end else begin
                             ln_base_val <= (z <<< 1) - e_ln2;
                             state <= S_DIV_PREP;
                        end
                    end
                end

                // Normalize Base
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

                // Division - Step 1
                S_DIV_PREP: begin
                    if (ln_base_val == 0) begin
                        final_fixed <= 32'h7FFF_FFFF;
                        state <= S_CONVERT;
                    end else begin
                        // FIX: Shift by 15 instead of 16 to correct the factor of 2 error
                        div_rem = {32'b0, ln_b_val} << 15; 
                        div_denom = ln_base_val;
                        div_quo = 0;
                        div_cnt = 32; 
                        state <= S_DIV_CALC;
                    end
                end

                // Division - Step 2 (Bit Serial)
                S_DIV_CALC: begin
                    
                    rem_shift = div_rem << 1;
                    sub_res = rem_shift[63:32] - {1'b0, div_denom};
                    
                    if (sub_res[32] == 0) begin // Positive
                        div_rem = {sub_res[31:0], rem_shift[31:0]};
                        div_quo = (div_quo << 1) | 1'b1;
                    end else begin // Negative
                        div_rem = rem_shift;
                        div_quo = (div_quo << 1) | 1'b0;
                    end
                    
                    if (div_cnt == 0) begin
                        final_fixed <= div_quo; 
                        state <= S_CONVERT;
                    end else begin
                        div_cnt <= div_cnt - 1;
                    end
                end

                // IEEE 754 Conversion
                S_CONVERT: begin
                    ieee_out[31] = final_fixed[31]; 
                    abs_final = final_fixed[31] ? -final_fixed : final_fixed;
                    
                    if (abs_final == 0) begin
                        ieee_out = 0;
                    end else begin
                        norm_shift = clz(abs_final);
                        ieee_exp = 142 - norm_shift;
                        ieee_mant = (abs_final << norm_shift) >> 8; 
                        ieee_out[30:23] = ieee_exp;
                        ieee_out[22:0]  = ieee_mant;
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