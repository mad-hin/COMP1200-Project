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
    input wire [7:0] sw,
    // 7-segment display outputs
    output wire [6:0] seg,
    output wire [3:0] an
);

    // Debounced button signals
    wire btn_left_db, btn_right_db, btn_up_db, btn_down_db, btn_mid_db;
    
    // Edge-detected button signals (rising edge)
    wire btn_left_edge, btn_right_edge, btn_up_edge, btn_down_edge, btn_mid_edge;
    
    // Input controller signals
    wire [1:0] current_digit;
    wire [`INPUTOUTBIT-1:0] input_val;
    wire [12:0] display_input;
    wire input_done;
    
    // Instantiate debouncers for all buttons
    debouncer #(.CNTW(20), .STABLE(200000)) db_left (
        .clk(clk),
        .rst(rst),
        .din(btn_left),
        .dout(btn_left_db)
    );
    
    debouncer #(.CNTW(20), .STABLE(200000)) db_right (
        .clk(clk),
        .rst(rst),
        .din(btn_right),
        .dout(btn_right_db)
    );
    
    debouncer #(.CNTW(20), .STABLE(200000)) db_up (
        .clk(clk),
        .rst(rst),
        .din(btn_up),
        .dout(btn_up_db)
    );
    
    debouncer #(.CNTW(20), .STABLE(200000)) db_down (
        .clk(clk),
        .rst(rst),
        .din(btn_down),
        .dout(btn_down_db)
    );
    
    debouncer #(.CNTW(20), .STABLE(200000)) db_mid (
        .clk(clk),
        .rst(rst),
        .din(btn_mid),
        .dout(btn_mid_db)
    );
    
    // Instantiate edge detectors for debounced buttons
    red ed_left (
        .clk(clk),
        .rst(rst),
        .din(btn_left_db),
        .rise(btn_left_edge)
    );
    
    red ed_right (
        .clk(clk),
        .rst(rst),
        .din(btn_right_db),
        .rise(btn_right_edge)
    );
    
    red ed_up (
        .clk(clk),
        .rst(rst),
        .din(btn_up_db),
        .rise(btn_up_edge)
    );
    
    red ed_down (
        .clk(clk),
        .rst(rst),
        .din(btn_down_db),
        .rise(btn_down_edge)
    );
    
    red ed_mid (
        .clk(clk),
        .rst(rst),
        .din(btn_mid_db),
        .rise(btn_mid_edge)
    );
    
    // Instantiate input controller
    input_controller input_ctrl (
        .clk(clk),
        .rst(rst),
        .bnt_left(btn_left_edge),
        .bnt_right(btn_right_edge),
        .bnt_up(btn_up_edge),
        .bnt_down(btn_down_edge),
        .btn_mid(btn_mid_edge),
        .current_digit(current_digit),
        .input_val(input_val),
        .display_input(display_input),
        .input_done(input_done)
    );
    
    // Instantiate output controller
    output_controller output_ctrl (
        .clk(clk),
        .display_input(display_input),
        .current_digit(current_digit),
        .seg(seg),
        .an(an)
    );
    
    // TODO: Add arithmetic operation modules here
    // - Use sw[7:0] to select operation
    // - Use input_done to trigger calculation
    // - Store operands A and B
    // - Compute result and update display_input
    
endmodule