`timescale 1ns / 1ps
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
    input wire signed [31:0] a,
    // input wire signed [31:0] b, // Removed unused port
    output reg signed [31:0] result, // 32 bit IEEE754
    output reg error,
    output reg done
);

    reg [3:0] state;
    localparam S_IDLE   = 0;
    localparam S_PREP   = 1;
    localparam S_CALC   = 2;
    localparam S_NORM   = 3;
    localparam S_DONE   = 4;

    // Registers expanded for High Precision
    // We calculate Sqrt(a * 2^32)
    reg [31:0] q;       // Quotient (Root)
    reg [33:0] r;       // Remainder (needs extra bits for shifting)
    reg [63:0] d;       // Data (holds a << 32)
    reg [5:0]  count;   // Iteration Counter (up to 32)
    
    // IEEE Conversion vars
    reg [5:0]  clz_val;
    reg [7:0]  ieee_exp;
    reg [22:0] mant;
    reg [31:0] q_final;

    // Helper: Count Leading Zeros
    function [5:0] clz;
        input [31:0] val;
        integer k;
        begin
            clz = 0;
            begin : clz_loop
                for (k = 31; k >= 0; k = k - 1) begin
                    if (val[k]) disable clz_loop;
                    clz = clz + 1;
                end
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            result <= 0;
            error <= 0;
            done <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    error <= 0;
                    if (start) state <= S_PREP;
                end

                S_PREP: begin
                    if (a <= 0) begin
                        if (a < 0) error <= 1; // Sqrt of negative is Error (NaN)
                        result <= 0; 
                        state <= S_DONE;
                    end else begin
                        // Load data and upscale by 2^32 for precision
                        // d = {a, 32'b0}
                        d = {a, 32'b0};
                        q = 0;
                        r = 0;
                        count = 0; 
                        state <= S_CALC;
                    end
                end

                // Binary Square Root Algorithm (32 iterations)
                S_CALC: begin
                    if (count < 32) begin
                        // Bring down next 2 bits from 'd'
                        r = (r << 2) | ((d >> 62) & 3);
                        d = d << 2;
                        q = q << 1;
                        
                        // Check if we can subtract
                        if (r >= (2 * q + 1)) begin
                            r = r - (2 * q + 1);
                            q = q + 1;
                        end
                        count <= count + 1;
                    end else begin
                        state <= S_NORM;
                    end
                end

                S_NORM: begin
                    // q now holds Sqrt(a * 2^32) = Sqrt(a) * 2^16
                    // We treat q as a Fixed Point number with 16 fractional bits.
                    
                    if (q == 0) begin
                        result <= 0;
                    end else begin
                        clz_val = clz(q);
                        
                        // Exponent Calculation:
                        // Real Value = q * 2^-16
                        // MSB of q is at bit (31 - clz_val)
                        // IEEE Exp = 127 + (Pos - 16)
                        //          = 127 + (31 - clz_val) - 16
                        //          = 142 - clz_val
                        ieee_exp = 142 - clz_val; 
                        
                        // Mantissa
                        mant = (q << clz_val) >> 8;
                        
                        result <= {1'b0, ieee_exp, mant};
                    end
                    state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule