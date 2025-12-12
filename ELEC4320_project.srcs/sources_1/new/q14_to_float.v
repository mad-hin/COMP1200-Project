`timescale 1ns / 1ps

// Q2.14 fixed to IEEE754 single precision
module q14_to_float (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [15:0] q14_value,
    output reg  [31:0] float_result,
    output reg  convert_valid,
    output reg  done
);
    reg [2:0] state;
    localparam IDLE=3'd0, ABS=3'd1, NORM=3'd2, PACK=3'd3, DONE_ST=3'd4;

    reg sign;
    reg [15:0] abs_val;
    reg [4:0] lead;
    reg [22:0] mant;
    reg [7:0] exp;
    reg [31:0] norm_shift;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; float_result <= 0; convert_valid <= 0; done <= 0;
            sign <= 0; abs_val <= 0; lead <= 0; mant <= 0; exp <= 0; norm_shift <= 0;
        end else begin
            case (state)
                IDLE: begin convert_valid <= 0; done <= 0; if (start) state <= ABS; end
                ABS: begin
                    sign    <= q14_value[15];
                    abs_val <= q14_value[15] ? (~q14_value + 1'b1) : q14_value;
                    if (abs_val == 0) begin float_result <= 32'h00000000; convert_valid <= 1; done <= 1; state <= DONE_ST; end
                    else state <= NORM;
                end
                NORM: begin
                    // find leading 1
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
                    else if (abs_val[2])  lead = 2;
                    else if (abs_val[1])  lead = 1;
                    else lead = 0;
                    state <= PACK;
                end
                PACK: begin
                    // Q2.14: binary point after bit14 => value = abs_val / 2^14
                    // Normalize: abs_val << (23 - lead) to place leading 1 at bit23
                    norm_shift = abs_val << (23 - lead);
                    mant = norm_shift[22:0];
                    exp  = 8'd127 + lead - 14; // bias adjust for Q2.14
                    float_result <= {sign, exp, mant};
                    convert_valid <= 1;
                    state <= DONE_ST;
                end
                DONE_ST: begin done <= 1; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end
endmodule