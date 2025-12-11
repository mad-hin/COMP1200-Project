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
    output reg [6:0] seg,
    output reg [3:0] an,
    output wire [15:0] led,
    output wire dp
);
    wire signed [`INPUTOUTBIT-1:0] result;
    wire cal_done;
    wire error;
    wire [6:0] alu_seg, display_seg;
    wire [3:0] alu_an, display_an;
    
    alu alu_inst (
        .clk(clk),
        .rst(rst),
        .sw(sw),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .btn_up(btn_up),
        .btn_down(btn_down),
        .btn_mid(btn_mid),
        .seg(alu_seg),
        .an(alu_an),
        .result(result),
        .cal_done(cal_done),
        .error(error)
    );

    display_controller display_inst (
        .clk(clk),
        .rst(rst),
        .result(result),
        .error(error),
        .seg(display_seg),
        .an(display_an),
        .led(led),
        .dp(dp),
        .start(cal_done)
    );

    always @(*) begin
        if (cal_done) begin
            seg = display_seg;
            an  = display_an;
        end else begin
            seg = alu_seg;
            an  = alu_an;
        end
    end
endmodule