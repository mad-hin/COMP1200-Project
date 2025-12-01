`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.10.2025 22:42:07
// Design Name: 
// Module Name: cal
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Top-level calculator module integrating input/output controllers
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`include "define.vh"

module cal(
    input wire clk,
    input wire rst,
    // Button inputs (raw, need debouncing)
    input wire btn_left,
    input wire btn_right,
    input wire btn_up,
    input wire btn_down,
    input wire btn_mid,
    // Switch inputs for operation selection
    input wire [3:0] sw,
    // 7-segment display outputs
    output wire [6:0] seg,
    output wire [3:0] an,
    output wire [15:0] led
);
    wire [`INPUTOUTBIT-1:0] result;
    wire cal_done;
    // TODO: Add arithmetic operation modules here
    // - Use sw[3:0] to select operation
    // - Use input_done to trigger calculation
    // - Store operands A and B
    // - Compute result and update display_input
    alu alu_inst (
        .clk(clk),
        .rst(rst),
        .sw(sw),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .btn_up(btn_up),
        .btn_down(btn_down),
        .btn_mid(btn_mid),
        .seg(seg),
        .an(an),
        .result(led),
        .cal_done(cal_done)
    );
endmodule