`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.11.2025 18:17:07
// Design Name: 
// Module Name: red
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


module red(
    input clk, 
    input rst, 
    input din, 
    output reg rise
    );
    
    reg d1;
    always @(posedge clk or posedge rst) begin
        if (rst) begin d1<=0; rise<=0; end
        else begin
            rise <= din & ~d1;
            d1   <= din;
        end
    end
endmodule
