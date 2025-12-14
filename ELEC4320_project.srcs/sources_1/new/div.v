`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 15:17:25
// Design Name: 
// Module Name: div
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


module div(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a,
    input wire signed [`INPUTOUTBIT-1:0] b,
    output reg signed [`INPUTOUTBIT-1:0] result, // BF16
    output reg error = 0,
    output reg done
);
    
    reg sign;
    integer leading;
    reg [`INPUTOUTBIT-1:0] dividend, divisor;
    reg [`INPUTOUTBIT-1:0] quotient;
    reg [`INPUTOUTBIT-1:0] remainder;
    
    reg [4:0] integer_count;
    reg [5:0] fraction_count;
    reg [7:0] fraction_bits;

    reg [23:0] combined;
    reg [7:0] bf16_exp;
    reg [6:0] bf16_mant;


    reg [1:0] state;

    localparam S_IDLE=0,
               S_INTDIV=1,
               S_FRACTIONDIV=2,
               S_OUTPUT=3;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done   <= 0;
            state<=S_IDLE;
        end else begin
            case (state)

            S_IDLE: begin
                done<=0;
                if (start) begin
                    if (b==0) begin
                        error<=1;
                        done<=1;
                    end else begin
                        sign<=a[`INPUTOUTBIT-1]^b[`INPUTOUTBIT-1];
                        dividend<=a[`INPUTOUTBIT-1]? -a: a;
                        divisor<=b[`INPUTOUTBIT-1]? -b: b;
                        quotient<=0;
                        remainder<=0;
                        integer_count<=`INPUTOUTBIT-1;
                        fraction_count<=0;
                        fraction_bits<=0;
                        state<=S_INTDIV;
                    end
                end
            end

            // Integer long division
            S_INTDIV: begin
                remainder=(remainder << 1)|(dividend[integer_count]);
                if (remainder>=divisor) begin
                    remainder=remainder-divisor;
                    quotient[integer_count]=1;
                end
                if (integer_count==0)
                    state<=S_FRACTIONDIV;
                else
                    integer_count<=integer_count-1;
            end

            // Fractional long division (7 bits for BF16)
            S_FRACTIONDIV: begin
                remainder=remainder<<1;
                if (remainder>=divisor) begin
                    remainder=remainder-divisor;
                    fraction_bits[7-fraction_count]=1;
                end else begin
                    fraction_bits[7-fraction_count]=0;
                end

                if (fraction_count==7)
                    state<=S_OUTPUT;
                else
                    fraction_count<=fraction_count+1;
            end

            // Convert to BF16 for output
            S_OUTPUT: begin
                combined={quotient, fraction_bits};
                
                leading=23;
                while (leading>=0 && combined[leading]==0)
                    leading=leading-1;

                if (leading<0) begin
                    // Result is zero
                    result<=16'b0;
                end else begin
                    bf16_exp=8'd127+(leading-8);
                    bf16_mant=(combined<<(23-leading))>>16;
                    result<={sign, bf16_exp, bf16_mant[6:0]};
                end

                state<=S_IDLE;
                done<=1;
            end
            endcase
        end
end
endmodule
