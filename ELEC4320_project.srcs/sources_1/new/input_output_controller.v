`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 14:01:58
// Design Name: 
// Module Name: input_output_controller
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


module input_output_controller(
    input wire clk,
    input wire rst,
    // Raw buttons
    input wire btn_left,
    input wire btn_right,
    input wire btn_up,
    input wire btn_down,
    input wire btn_mid,
    input wire reset_input,
    // Outputs to 7-segment
    output wire [6:0] seg,
    output wire [3:0] an,

    // Returned input value (packed as defined in define.vh)
    output wire [`INPUTOUTBIT-1:0] input_val,
    output wire input_done
);
    // Generate slower clock for input controller (100MHz from 300MHz)
    wire clk_slow;
    clock_divider #(.DIV_FACTOR(3)) clk_div (
        .clk_in(clk),
        .rst(rst),
        .clk_out(clk_slow)
    );

    // Debounced button signals - use slower clock
    wire btn_left_db, btn_right_db, btn_up_db, btn_down_db, btn_mid_db;

    // Use 2 ms debounce at 100 MHz => STABLE = 200000
    debouncer #(.CNTW(18), .STABLE(200000)) db_left(.clk(clk_slow), .rst(rst), .din(btn_left),.dout(btn_left_db));
    debouncer #(.CNTW(18), .STABLE(200000)) db_right (.clk(clk_slow), .rst(rst), .din(btn_right), .dout(btn_right_db));
    debouncer #(.CNTW(18), .STABLE(200000)) db_up(.clk(clk_slow), .rst(rst), .din(btn_up),.dout(btn_up_db));
    debouncer #(.CNTW(18), .STABLE(200000)) db_down(.clk(clk_slow), .rst(rst), .din(btn_down),.dout(btn_down_db));
    debouncer #(.CNTW(18), .STABLE(200000)) db_mid (.clk(clk_slow), .rst(rst), .din(btn_mid), .dout(btn_mid_db));

    // Rising-edge detectors - use slower clock
    wire e_left, e_right, e_up, e_down, e_mid;
    red ed_left(.clk(clk_slow), .rst(rst), .din(btn_left_db),.rise(e_left));
    red ed_right (.clk(clk_slow), .rst(rst), .din(btn_right_db), .rise(e_right));
    red ed_up(.clk(clk_slow), .rst(rst), .din(btn_up_db),.rise(e_up));
    red ed_down(.clk(clk_slow), .rst(rst), .din(btn_down_db),.rise(e_down));
    red ed_mid (.clk(clk_slow), .rst(rst), .din(btn_mid_db), .rise(e_mid));

    // Input and display
    wire [1:0]current_digit;
    wire [12:0] display_input;

    input_controller u_inp (
        .clk(clk_slow),
        .rst(rst | reset_input),
        .bnt_left(e_left),
        .bnt_right(e_right),
        .bnt_up(e_up),
        .bnt_down(e_down),
        .btn_mid(e_mid),
        .current_digit(current_digit),
        .input_val(input_val),
        .display_input(display_input),
        .input_done(input_done)
    );

    // Output controller can still use fast clock for smooth display
    output_controller u_out (
        .clk(clk_slow),
        .display_input(display_input),
        .current_digit(current_digit),
        .seg(seg),
        .an(an)
    );
endmodule
