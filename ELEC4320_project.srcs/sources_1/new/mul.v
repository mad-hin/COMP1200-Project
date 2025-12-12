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
    output reg signed [`INPUTOUTBIT-1:0] result, // 32 bit IEEE754
    output reg error = 0,
    output reg done
);

    
    // Stage 1: Multiplication
    reg signed [2*`INPUTOUTBIT-1:0] prod_stage1;
    reg valid_s1;

    // Stage 2: Absolute Value & Sign
    reg [2*`INPUTOUTBIT-1:0] abs_prod_stage2;
    reg sign_stage2;
    reg valid_s2;

    // Stage 3: Leading Zero/One Detection (Exponent Prep)
    reg [5:0] leading_pos_stage3;
    reg [2*`INPUTOUTBIT-1:0] abs_prod_stage3;
    reg sign_stage3;
    reg valid_s3;
    reg [7:0] final_exp;
    reg [22:0] final_mant;
    reg [63:0] shifted_mant;

    function [5:0] get_leading_one;
        input [63:0] val;
        integer i;
        begin
            get_leading_one = 0;
            // Scan from bit 63 down to 0
            for (i = 0; i < 64; i = i + 1) begin
                if (val[i]) get_leading_one = i[5:0];
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result    <= 0;
            done      <= 0;
            error     <= 0;
            valid_s1  <= 0;
            valid_s2  <= 0;
            valid_s3  <= 0;
        end else begin
            
            if (start) begin
                prod_stage1 <= a * b;
                valid_s1    <= 1;
                done        <= 0; // Reset done when new calc starts
            end else begin
                valid_s1    <= 0;
            end

            if (valid_s1) begin
                sign_stage2 <= prod_stage1[2*`INPUTOUTBIT-1];
                // If negative, invert. If positive, pass through.
                abs_prod_stage2 <= prod_stage1[2*`INPUTOUTBIT-1] ? -prod_stage1 : prod_stage1;
                valid_s2 <= 1;
            end else begin
                valid_s2 <= 0;
            end

            if (valid_s2) begin
                // Find the index of the highest set bit
                leading_pos_stage3 <= get_leading_one(abs_prod_stage2);
                abs_prod_stage3    <= abs_prod_stage2;
                sign_stage3        <= sign_stage2;
                valid_s3           <= 1;
            end else begin
                valid_s3 <= 0;
            end

            if (valid_s3) begin
                if (abs_prod_stage3 == 0) begin
                    result <= 0;
                end else begin
                    final_exp = 8'd127 + leading_pos_stage3;        
                    if (leading_pos_stage3 >= 23) begin
                        shifted_mant = abs_prod_stage3 >> (leading_pos_stage3 - 23);
                    end else begin
                        shifted_mant = abs_prod_stage3 << (23 - leading_pos_stage3);
                    end
                    // Mask out the hidden 1 (bit 23) and take lower 23 bits
                    final_mant = shifted_mant[22:0];
                    result <= {sign_stage3, final_exp, final_mant};
                end
                
                done <= 1;
            end else begin
                done <= 0;
            end
        end
    end

endmodule