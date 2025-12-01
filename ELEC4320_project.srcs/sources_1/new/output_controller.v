`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.11.2025 21:07:23
// Design Name: 
// Module Name: output_controller
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


module output_controller(
    input clk,
    input [12:0] display_input,
    input [1:0]  current_digit,
    output reg [6:0] seg,
    output reg [3:0] an
);
    reg [25:0] refresh_cnt;
    always @(posedge clk) refresh_cnt <= refresh_cnt + 1'b1;

    wire [1:0] mux_sel = refresh_cnt[18:17]; // scan digits fast enough
    wire blink = refresh_cnt[25];

    wire is_selected = (mux_sel == current_digit);

    reg [3:0] digit_val;
    reg is_sign_digit;

    always @* begin
        is_sign_digit = 1'b0;
        case(mux_sel)
            2'b00: begin an = 4'b1110; digit_val = display_input[3:0];  end
            2'b01: begin an = 4'b1101; digit_val = display_input[7:4];   end
            2'b10: begin an = 4'b1011; digit_val = display_input[11:8];  end
            2'b11: begin an = 4'b0111; digit_val = 4'hA; is_sign_digit = 1'b1; end
            default: begin an = 4'b1111; digit_val = 4'hF; end
        endcase
    end

    function [6:0] enc7;
        input [3:0] d;
        input sign;
        input sign_digit;
        begin
            if (sign_digit) enc7 = sign ? 7'b0111111 : 7'b1111111; // '-' or blank
            else case(d)
                4'd0: enc7=7'b1000000;
                4'd1: enc7=7'b1111001;
                4'd2: enc7=7'b0100100;
                4'd3: enc7=7'b0110000;
                4'd4: enc7=7'b0011001;
                4'd5: enc7=7'b0010010;
                4'd6: enc7=7'b0000010;
                4'd7: enc7=7'b1111000;
                4'd8: enc7=7'b0000000;
                4'd9: enc7=7'b0010000;
                default: enc7=7'b1111111;
            endcase
        end
    endfunction

    always @* begin
        if (is_selected && blink)
            seg = 7'b1111111;
        else
            seg = enc7(digit_val, display_input[12], is_sign_digit);
    end
endmodule
