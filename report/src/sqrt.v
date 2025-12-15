`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 16:05:57
// Design Name: 
// Module Name: sqrt
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
module sqrt(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a,
    output reg signed [`INPUTOUTBIT-1:0] result, // BF16
    output reg error,
    output reg done
);

    reg [2:0] state;
    localparam S_IDLE=0;
    localparam S_PREPRATION=1;
    localparam S_CALCULATION=2;
    localparam S_NORM=3;
    localparam S_DONE=4;

    // Registers for High Precision
    // We calculate Sqrt(a * 2^16) = Sqrt(a) * 2^8
    reg [`INPUTOUTBIT-1:0] quotient;       // Quotient (Root)
    reg [`INPUTOUTBIT+1:0] remainder;       // Remainder (needs extra bits for shifting)
    reg [2*`INPUTOUTBIT-1:0] data;       // Data (holds a << 16)
    reg [4:0]  count;   // Iteration Counter (up to 16)
    
    // BF16 Conversion vars
    reg [4:0]  clz_val;
    reg [7:0]  bf16_exp;
    reg [6:0]  bf16_mant;
    reg [15:0] q_shifted;

    // Helper: Count Leading Zeros
    function [4:0] clz;
        input [`INPUTOUTBIT-1:0] val;
        integer k;
        begin
            clz = 0;
            begin : clz_loop
                for (k=`INPUTOUTBIT-1; k>=0; k=k-1) begin
                    if (val[k]) disable clz_loop;
                    clz=clz+1;
                end
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=S_IDLE;
            result<=0;
            error<=0;
            done<=0;
        end else begin
            case (state)
                S_IDLE: begin
                    done<=0;
                    error<=0;
                    if (start) state<=S_PREPRATION;
                end

                S_PREPRATION: begin
                    if (a <= 0) begin
                        // Sqrt of negative is Error
                        if (a < 0) 
                            error<=1;
                        state<=S_DONE;
                    end else begin
                        // Load data and upscale by 2^32 for precision
                        data={a, 16'b0};
                        quotient=0;
                        remainder=0;
                        count=0; 
                        state<=S_CALCULATION;
                    end
                end

                // Binary Square Root Algorithm (16 iterations)
                S_CALCULATION: begin
                    if (count<16) begin
                        // Bring down next 2 bits from 'data'
                        remainder=(remainder<<2)|((data>>30)&2'b11);
                        data=data<<2;
                        quotient=quotient<<1;
                        
                        // Check if we can subtract
                        if (remainder>=(2*quotient+1)) begin
                            remainder=remainder-(2*quotient+1);
                            quotient=quotient+1;
                        end
                        count<=count+1;
                    end else begin
                        state<=S_NORM;
                    end
                end

                S_NORM: begin
                    // quotient now holds Sqrt(a * 2^16) = Sqrt(a) * 2^8
                    // We treat quotient as a Fixed Point number with 8 fractional bits.
                    
                    if (quotient==0) begin
                        result<=0;
                    end else begin
                        clz_val=clz(quotient);
                        
                        // Exponent Calculation:
                        // Real Value = q * 2^-8
                        // MSB of q is at bit (15 - clz_val)
                        // BF16 Exp = 127 + (Pos - 8)
                        //          = 127 + (15 - clz_val) - 8
                        //          = 134 - clz_val
                        bf16_exp=8'd134-{3'b0, clz_val}; 
                        
                        // Mantissa
                        q_shifted=quotient<<clz_val;
                        bf16_mant=q_shifted[14:8];
                        
                        result<={1'b0, bf16_exp, bf16_mant};
                    end
                    state<=S_DONE;
                end

                S_DONE: begin
                    done<=1;
                    if (!start) state<=S_IDLE;
                end
            endcase
        end
    end

endmodule