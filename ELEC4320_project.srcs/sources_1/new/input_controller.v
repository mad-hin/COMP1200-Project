`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.11.2025 23:39:51
// Design Name: 
// Module Name: input_controller
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


module input_controller(
    input clk, rst, bnt_left, bnt_right, bnt_up, bnt_down, btn_mid,
    output reg [1:0] current_digit,
    output reg signed [`INPUTOUTBIT - 1 :0] input_val,
    output reg [12:0] display_input, // 1st bit is sign, next every 4 bits is a digit, i.e. {sign, hundreds, tens, units}
    output reg input_done 
    );
    reg input_done_latched;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_digit <= 4'b0000;
            input_val <= 0;
            display_input <= 13'b0000000000000;
            input_done <= 1'b0;
            input_done_latched <= 1'b0;
        end
        else begin
            // Navigate between digits
            if (bnt_left) begin
                // Ignore if already at the leftmost digit
                if (current_digit < 3)
                    current_digit <= current_digit + 1;
            end
            else if (bnt_right) begin
                // Ignore if already at the rightmost digit
                if (current_digit > 0)
                    current_digit <= current_digit - 1;
            end

            // Modify digit values
            if (bnt_up) begin
                case (current_digit)
                    2'b00: display_input[3:0] <= (display_input[3:0] + 1) % 10; // units
                    2'b01: display_input[7:4] <= (display_input[7:4] + 1) % 10; // tens
                    2'b10: display_input[11:8] <= (display_input[11:8] + 1) % 10; // hundreds
                    2'b11: display_input[12] <= ~display_input[12]; // sign bit
                endcase
            end
            else if (bnt_down) begin
                case (current_digit)
                    2'b00: display_input[3:0] <= (display_input[3:0] + 9) % 10; // units
                    2'b01: display_input[7:4] <= (display_input[7:4] + 9) % 10; // tens
                    2'b10: display_input[11:8] <= (display_input[11:8] + 9) % 10; // hundreds
                    2'b11: display_input[12] <= ~display_input[12]; // sign bit
                endcase
            end

            // Confirm input
            if (btn_mid) begin
                if (display_input[12]) begin
                    input_val <= -(display_input[11:8] * 100 + display_input[7:4] * 10 + display_input[3:0]);
                end else begin
                    input_val <= display_input[11:8] * 100 + display_input[7:4] * 10 + display_input[3:0];
                end
                input_done_latched <= 1'b1;
            end
            input_done <= input_done_latched;
        end
    end
endmodule
