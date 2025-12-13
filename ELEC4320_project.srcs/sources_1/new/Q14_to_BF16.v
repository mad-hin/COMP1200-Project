`timescale 1ns / 1ps

// Q2.14 fixed to BF16 (16-bit brain floating point)
module Q14_to_BF16 (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [15:0] q14_value,  // Q2.14 format
    output reg  [15:0] float_result,      // BF16 format: 1s,8e,7m
    output reg  convert_valid,
    output reg  done
);
    reg [2:0] state;
    localparam IDLE=3'd0, ABS=3'd1, NORM=3'd2, PACK=3'd3, DONE_ST=3'd4;

    reg sign;
    reg [15:0] abs_val;
    reg [3:0] lead;     // leading 1 position (0-15)
    reg [6:0] mant;     // 7-bit mantissa for BF16
    reg [7:0] exp;      // 8-bit exponent for BF16
    reg [15:0] shifted_abs;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; float_result <= 0; convert_valid <= 0; done <= 0;
            sign <= 0; abs_val <= 0; lead <= 0; mant <= 0; exp <= 0; shifted_abs <= 0;
        end else begin
            case (state)
                IDLE: begin convert_valid <= 0; done <= 0; if (start) state <= ABS; end
                ABS: begin
                    sign    <= q14_value[15];
                    abs_val <= q14_value[15] ? (~q14_value + 1'b1) : q14_value;
                    if (abs_val == 0) begin 
                        // Zero: sign=0, exp=0, mant=0
                        float_result <= 16'h0000; 
                        convert_valid <= 1; 
                        done <= 1; 
                        state <= DONE_ST; 
                    end else begin
                        state <= NORM;
                    end
                end
                NORM: begin
                    // Find leading 1 in 16-bit abs_val
                    if      (abs_val[15]) lead = 15;
                    else if (abs_val[14]) lead = 14;
                    else if (abs_val[13]) lead = 13;
                    else if (abs_val[12]) lead = 12;
                    else if (abs_val[11]) lead = 11;
                    else if (abs_val[10]) lead = 10;
                    else if (abs_val[9])  lead = 9;
                    else if (abs_val[8])  lead = 8;
                    else if (abs_val[7])  lead = 7;
                    else if (abs_val[6])  lead = 6;
                    else if (abs_val[5])  lead = 5;
                    else if (abs_val[4])  lead = 4;
                    else if (abs_val[3])  lead = 3;
                    else if (abs_val[2]) lead = 2;
                    else if (abs_val[1]) lead = 1;
                    else lead = 0;
                    state <= PACK;
                end
                PACK: begin
                    // Q2.14: binary point at bit14, value = abs_val * 2^(-14)
                    // For BF16: exponent bias = 127 (same as IEEE754)
                    // exp_biased = lead - 14 + 127 = lead + 113
                    exp = lead + 8'd113;
                    
                    // Handle overflow: exp >= 255 -> infinity
                    if (exp >= 8'd255) begin
                        // ±Infinity: sign, exp=0xFF, mant=0
                        float_result <= {sign, 8'hFF, 7'h00};
                    end else begin
                        // Normalize: shift so leading 1 is at bit15
                        shifted_abs = abs_val << (15 - lead);
                        // Extract mantissa: bits[14:8] (7 bits)
                        mant = shifted_abs[14:8];
                        float_result <= {sign, exp, mant};
                    end
                    convert_valid <= 1;
                    state <= DONE_ST;
                end
                DONE_ST: begin done <= 1; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end
endmodule