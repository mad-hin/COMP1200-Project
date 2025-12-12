`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 15:23:15
// Design Name: 
// Module Name: add
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


module add(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a,
    input wire signed [`INPUTOUTBIT-1:0] b,
    input wire add_sub_flag, // 0:add, 1:sub
    output reg signed [`INPUTOUTBIT-1:0] result, // 32 bit IEEE754
    output reg error = 0,
    output reg done
);
    reg signed [`INPUTOUTBIT-1:0] diff;
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;
    integer leading;

    reg [4:0]  lz;
    reg [4:0]  shift_amt;
    reg [31:0] diff_abs, diff_abs_s;
    reg [31:0] s0, s1, s2, s3, s4;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done   <= 0;
        end else if (start) begin
            diff = add_sub_flag ? (a - b) : (a + b);
            if (diff == 0) begin
                result <= 32'b0;
            end else begin
                sign = diff[`INPUTOUTBIT-1];
                diff_abs = sign ? -diff : diff;

                // leading-zero detector (5-level tree)
                lz = 0;
                if (diff_abs[31:16] == 0) begin lz = lz + 16; diff_abs_s = diff_abs[15:0];  end else diff_abs_s = diff_abs[31:16];
                if (diff_abs_s[15:8] == 0) begin lz = lz + 8;  diff_abs_s = diff_abs_s[7:0]; end else diff_abs_s = diff_abs_s[15:8];
                if (diff_abs_s[7:4]  == 0) begin lz = lz + 4;  diff_abs_s = diff_abs_s[3:0]; end else diff_abs_s = diff_abs_s[7:4];
                if (diff_abs_s[3:2]  == 0) begin lz = lz + 2;  diff_abs_s = diff_abs_s[1:0]; end else diff_abs_s = diff_abs_s[3:2];
                if (diff_abs_s[1]    == 0) lz = lz + 1;

                shift_amt = lz;                // number of leading zeros
                leading   = 31 - lz;           // MSB index
                exp       = 8'd127 + leading;

                // barrel shift left by shift_amt (5-stage)
                s0 = (shift_amt[4]) ? (diff_abs << 16) : diff_abs;
                s1 = (shift_amt[3]) ? (s0 << 8 ) : s0;
                s2 = (shift_amt[2]) ? (s1 << 4 ) : s1;
                s3 = (shift_amt[1]) ? (s2 << 2 ) : s2;
                s4 = (shift_amt[0]) ? (s3 << 1 ) : s3;

                mant = s4[31:9]; // keep 23 bits (hidden '1' dropped)
                result <= {sign, exp, mant};
            end
            done <= 1;
        end else begin
            done <= 0;
        end
    end
endmodule
