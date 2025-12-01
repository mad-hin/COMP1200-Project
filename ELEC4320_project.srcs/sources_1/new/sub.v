`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 18:29:59
// Design Name: 
// Module Name: sub
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

module sub(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [`INPUTOUTBIT-1:0] a,
    input wire [`INPUTOUTBIT-1:0] b,
    output reg [`INPUTOUTBIT-1:0] result,
    output reg done
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done <= 0;
        end else if (start) begin
            result <= a - b;
            done <= 1;
        end else begin
            done <= 0;
        end
    end
endmodule
