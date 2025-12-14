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
    output reg signed [`INPUTOUTBIT-1:0] result, // BF16
    output reg error = 0,
    output reg done
);

    reg signed [2*`INPUTOUTBIT-1:0] mutilple;
    reg valid_s1;

    reg [2*`INPUTOUTBIT-1:0] absolute_value;
    reg sign_stage2;
    reg valid_s2;

    reg [5:0] leading;
    reg [2*`INPUTOUTBIT-1:0] abs_mutilple;
    reg sign_stage3;
    reg valid_s3;

    reg [7:0] bf16_exp;          
    reg [6:0] bf16_mant;         
    reg [31:0] shifted_mant;

    function [5:0] get_leading;
        input [2*`INPUTOUTBIT-1:0] val;
        integer i;
        begin
            get_leading = 0;
            // Scan from bit 31 down to 0
            for (i = 0; i < 32; i = i + 1) begin
                if (val[i])get_leading=i[5:0];
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result<=0;
            done<=0;
            error<=0;
            valid_s1<=0;
            valid_s2<=0;
            valid_s3<=0;
        end else begin
            
            if (start) begin
                mutilple<=a*b;
                valid_s1<=1;
                done<=0; 
            end else begin
                valid_s1<=0;
            end

            if (valid_s1) begin
                sign_stage2<=mutilple[2*`INPUTOUTBIT-1];
                // If negative, invert. If positive, pass through.
                absolute_value<=mutilple[2*`INPUTOUTBIT-1]? -mutilple:mutilple;
                valid_s2<=1;
            end else begin
                valid_s2<=0;
            end

            if (valid_s2) begin
                // Find the index of the highest set bit
                leading<=get_leading(absolute_value);
                abs_mutilple<=absolute_value;
                sign_stage3<=sign_stage2;
                valid_s3<=1;
            end else begin
                valid_s3<=0;
            end

            if (valid_s3) begin
                if (abs_mutilple==0) begin
                    result<=0;
                end else begin
                    bf16_exp=8'd127+leading;    
                    // Shift to get the 7 fractional bits after the hidden 1   
                    if (leading>=7) begin
                        shifted_mant=abs_mutilple>>(leading-7);
                    end else begin
                        shifted_mant=abs_mutilple<<(7-leading);
                    end
                    // Mask out the hidden 1 (bit 7) and take lower 7 bits
                    bf16_mant=shifted_mant[6:0];
                    result<={sign_stage3, bf16_exp, bf16_mant};
                end
                
                done <= 1;
            end else begin
                done <= 0;
            end
        end
    end

endmodule