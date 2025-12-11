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
    output reg signed [`INPUTOUTBIT-1:0] result, // 32 bit IEEE754
    output reg error = 0,
    output reg done
);
    reg signed [`INPUTOUTBIT-1:0] diff;
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;
    integer leading;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done   <= 0;
        end else if (start) begin
            diff     = a + b;
            if (diff == 0) begin
                result <= 32'b0;
            end else begin
                sign = diff[`INPUTOUTBIT-1];
                if (sign) diff = -diff;
                // Have no idea why for loop don't work, so use the dumb way
                if (diff[31]) leading = 31;
                else if (diff[30]) leading = 30;
                else if (diff[29]) leading = 29;
                else if (diff[28]) leading = 28;
                else if (diff[27]) leading = 27;
                else if (diff[26]) leading = 26;
                else if (diff[25]) leading = 25;
                else if (diff[24]) leading = 24;
                else if (diff[23]) leading = 23;
                else if (diff[22]) leading = 22;
                else if (diff[21]) leading = 21;
                else if (diff[20]) leading = 20;
                else if (diff[19]) leading = 19;
                else if (diff[18]) leading = 18;
                else if (diff[17]) leading = 17;
                else if (diff[16]) leading = 16;
                else if (diff[15]) leading = 15;
                else if (diff[14]) leading = 14;
                else if (diff[13]) leading = 13;
                else if (diff[12]) leading = 12;
                else if (diff[11]) leading = 11;
                else if (diff[10]) leading = 10;
                else if (diff[9])  leading = 9;
                else if (diff[8])  leading = 8;
                else if (diff[7])  leading = 7;
                else if (diff[6])  leading = 6;
                else if (diff[5])  leading = 5;
                else if (diff[4])  leading = 4;
                else if (diff[3])  leading = 3;
                else if (diff[2])  leading = 2;
                else if (diff[1])  leading = 1;
                else leading = 0;
                exp = 8'd127 + leading;
                mant = diff << (23 - leading);
                result <= {sign, exp, mant[22:0]};
            end
            done <= 1;
        end else begin
            done <= 0;
        end
    end
endmodule
