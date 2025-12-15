`timescale 1ns / 1ps

`include "define.vh"
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 15:23:15
// Design Name: 
// Module Name: add
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: BF16 adder/subtractor (INPUTOUTBIT = 16, bfloat16 format)
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module add(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a,
    input wire signed [`INPUTOUTBIT-1:0] b,
    input wire add_sub_flag, // 0:add, 1:sub
    output reg signed [`INPUTOUTBIT-1:0] result, // 16 bit BF16
    output reg error = 0,
    output reg done
);
    reg signed [`INPUTOUTBIT-1:0] diff;
    reg sign;
    reg [7:0] exp;
    reg [6:0] mant;
    integer leading;

    reg [4:0]  lz;
    reg [4:0]  shift_amt;
    reg [15:0] diff_abs, diff_abs_s;
    reg [15:0] s0, s1, s2, s3;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done   <= 0;
        end else if (start) begin
            diff = add_sub_flag ? (a - b) : (a + b);
            if (diff == 0) begin
                result <= 16'b0;
            end else begin
                sign = diff[`INPUTOUTBIT-1];
                diff_abs = sign ? -diff : diff;

                // leading-zero detector for 16-bit (4-level tree)
                lz = 0;
                if (diff_abs[15:8] == 0) begin lz = lz + 8; diff_abs_s = diff_abs[7:0];  end else diff_abs_s = diff_abs[15:8];
                if (diff_abs_s[7:4]  == 0) begin lz = lz + 4; diff_abs_s = diff_abs_s[3:0]; end else diff_abs_s = diff_abs_s[7:4];
                if (diff_abs_s[3:2]  == 0) begin lz = lz + 2; diff_abs_s = diff_abs_s[1:0]; end else diff_abs_s = diff_abs_s[3:2];
                if (diff_abs_s[1]    == 0) lz = lz + 1;

                shift_amt = lz;                // number of leading zeros (0..15)
                leading   = 15 - lz;           // MSB index for 16-bit
                exp       = 8'd127 + leading;  // BF16 uses same bias (127)

                // barrel shift left by shift_amt (4-stage: 8,4,2,1)
                s0 = (shift_amt[3]) ? (diff_abs << 8) : diff_abs;
                s1 = (shift_amt[2]) ? (s0 << 4 ) : s0;
                s2 = (shift_amt[1]) ? (s1 << 2 ) : s1;
                s3 = (shift_amt[0]) ? (s2 << 1 ) : s2;

                mant = s3[14:8]; // keep 7 bits (first '1' dropped)
                result <= {sign, exp, mant};
            end
            done <= 1;
        end else begin
            done <= 0;
        end
    end
endmodule
