`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 13:37:35
// Design Name: 
// Module Name: mul
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


module mul(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a,
    input wire signed [`INPUTOUTBIT-1:0] b,
    output reg signed [`INPUTOUTBIT-1:0] result, // 32 bit IEEE754
    output reg error = 0,
    output reg done
);
    reg signed [`INPUTOUTBIT-1:0] multiple;
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;
    integer leading;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done   <= 0;
        end 
        else if (start) begin
            multiple=a*b;
            
            if (multiple == 0) begin
                result <= 32'b0;
            end
            else begin
                 sign=multiple[`INPUTOUTBIT-1];
                if (sign)
                    multiple=~multiple+1;
                
                leading=`INPUTOUTBIT-1;
                while (leading>=0&&multiple[leading]==0)
                    leading=leading-1;

                exp=8'd127 + leading;
                mant=multiple << (23 - leading)& 32'h7FFFFF;
                result<={sign, exp, mant[22:0]};
            end
            done <= 1;
        end 
        else begin
            done <= 0;
        end
    end
endmodule