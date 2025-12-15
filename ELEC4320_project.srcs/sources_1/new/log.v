`timescale 1ns / 1ps

`include "define.vh"
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
    input  wire signed [`INPUTOUTBIT-1:0] a,   
    input  wire signed [`INPUTOUTBIT-1:0] b,      
    output reg [`INPUTOUTBIT-1:0] result,  // BF16
    output reg  error,
    output reg  done
);

    localparam signed [`INPUTOUTBIT-1:0] ln2_fixed_point = 32'h0000_B172; 
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
    // reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i; 
    reg repeat_done; 
    
    reg signed [31:0] ln_b_val;
    reg signed [31:0] ln_base_val;
    reg signed [31:0] final_fixed; 
    
    // Store input values on start
    reg signed [`INPUTOUTBIT-1:0] a_reg, b_reg;

    // Division Signals
    reg [63:0] div_rem;   
    reg [31:0] div_quo;   
    reg [31:0] div_denom; 
    reg [5:0]  div_cnt;   

    reg signed [31:0] atanh_val;
    
    // Combinational: shift_count and current_input
    wire [5:0] shift_count_b;
    wire [5:0] shift_count_a;
    wire signed [31:0] current_input_b;
    wire signed [31:0] current_input_a;
    wire signed [31:0] e_ln2_b;
    wire signed [31:0] e_ln2_a;
    
    assign shift_count_b = clz(b_reg);
    assign shift_count_a = clz(a_reg);
    assign current_input_b = ($unsigned(b_reg) << shift_count_b) >> 16;
    assign current_input_a = ($unsigned(a_reg) << shift_count_a) >> 16;
    assign e_ln2_b = (32 - shift_count_b) * ln2_fixed_point;
    assign e_ln2_a = (32 - shift_count_a) * ln2_fixed_point;
    
    // Combinational: BF16 conversion
    wire [31:0] abs_final_w;
    wire [5:0]  norm_shift_w;
    wire [7:0]  bf16_exp_w;
    wire [6:0]  bf16_mant_w;
    wire [15:0] bf16_out_w;
    
    assign abs_final_w = final_fixed[31] ? -final_fixed : final_fixed;
    assign norm_shift_w = clz(abs_final_w);
    assign bf16_exp_w = 8'd127 + (8'd31 - {2'b0, norm_shift_w}) - 8'd15;
    assign bf16_mant_w = (abs_final_w << norm_shift_w) >> 24;
    assign bf16_out_w = (abs_final_w == 0) ? 16'b0 : {final_fixed[31], bf16_exp_w, bf16_mant_w};

    // Combinational: Division step
    wire [63:0] rem_shift_w;
    wire [32:0] sub_res_w;
    
    assign rem_shift_w = div_rem << 1;
    assign sub_res_w = rem_shift_w[63:32] - {1'b0, div_denom};

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

    always @(posedge clk or posedge rst) begin
        
        if (rst) begin
            state <= S_IDLE;
            result <= 0;
            error <= 0;
            done <= 0;
            i <= 1;
            repeat_done <= 0;
            x <= 0; 
            y <= 0; 
            z <= 0;
            // x_next <= 0;
            // y_next <= 0;
            // z_next <= 0;
            ln_b_val <= 0;
            ln_base_val <= 0;
            final_fixed <= 0;
            a_reg <= 0;
            b_reg <= 0;
            div_rem <= 0;
            div_quo <= 0;
            div_denom <= 0;
            div_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    error <= 0;
                    if (start) begin
                        // Capture inputs on start
                        a_reg <= a;
                        b_reg <= b;
                        state <= S_VALIDATE;
                    end
                end

                S_VALIDATE: begin
                    if (b_reg <= 0 || a_reg <= 0 || a_reg == 1) begin
                        error <= 1;
                        state <= S_DONE;
                    end else begin
                        state <= S_PREP_B;
                    end
                end

                // Normalize B
                S_PREP_B: begin
                    x <= current_input_b + 32'h0001_0000;
                    y <= current_input_b - 32'h0001_0000;
                    z <= (32 - shift_count_b) * ln2_fixed_point;
                    i <= 1;
                    repeat_done <= 0;
                    state <= S_CALC_B;
                end

                // CORDIC Core
                S_CALC_B, S_CALC_BASE: begin
                    if (i <= ITERATIONS) begin
                        // Directly update x, y, z
                        if (y[31] == 0) begin 
                            x <= x - (y >>> i);
                            y <= y - (x >>> i);
                            z <= z + atanh_val; 
                        end else begin 
                            x <= x + (y >>> i);
                            y <= y + (x >>> i);
                            z <= z - atanh_val;
                        end
                        
                        // Handle iteration counter with repeat for i=4 and i=13
                        if ((i == 4 || i == 13) && repeat_done == 0) begin
                            repeat_done <= 1; 
                        end else begin
                            i <= i + 1;
                            repeat_done <= 0; 
                        end
                    end else begin
                        // CORDIC complete, save result and move to next state
                        if (state == S_CALC_B) begin
                            ln_b_val <= (z <<< 1) - e_ln2_b; 
                            state <= S_PREP_BASE;
                        end else begin
                            ln_base_val <= (z <<< 1) - e_ln2_a;
                            state <= S_DIV_PREP;
                        end
                    end
                end

                // Normalize Base
                S_PREP_BASE: begin
                    x <= current_input_a + 32'h0001_0000; 
                    y <= current_input_a - 32'h0001_0000; 
                    z <= (32 - shift_count_a) * ln2_fixed_point; 
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
                        div_rem <= {32'b0, ln_b_val} << 15; 
                        div_denom <= ln_base_val;
                        div_quo <= 0;
                        div_cnt <= 32; 
                        state <= S_DIV_CALC;
                    end
                end

                // Division - Step 2 (Bit Serial)
                S_DIV_CALC: begin
                    if (sub_res_w[32] == 0) begin // Positive
                        div_rem <= {sub_res_w[31:0], rem_shift_w[31:0]};
                        div_quo <= (div_quo << 1) | 1'b1;
                    end else begin // Negative
                        div_rem <= rem_shift_w;
                        div_quo <= (div_quo << 1) | 1'b0;
                    end
                    
                    if (div_cnt == 0) begin
                        final_fixed <= div_quo; 
                        state <= S_CONVERT;
                    end else begin
                        div_cnt <= div_cnt - 1;
                    end
                end

                // BF16 Conversion
                S_CONVERT: begin
                    result <= bf16_out_w;
                    state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule