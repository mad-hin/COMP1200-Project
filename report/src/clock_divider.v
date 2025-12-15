`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 17:48:41
// Design Name: 
// Module Name: clock_divider
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


module clock_divider #(
    parameter DIV_FACTOR = 300 // Divide 300MHz to 1MHz by default
  )(
    input wire clk_in,
    input wire rst,
    output reg clk_out
    );
    reg [$clog2(DIV_FACTOR)-1:0] counter;

    always @(posedge clk_in or posedge rst) begin
        if (rst) begin
            counter <= 0;
            clk_out <= 0;
        end else begin
            if (counter == DIV_FACTOR/2 - 1) begin
                counter <= 0;
                clk_out <= ~clk_out;
            end else begin
                counter <= counter + 1;
            end
        end
    end
endmodule
