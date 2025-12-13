`timescale 1ns / 1ps

// Simple BF16 divider: result = a / b
module bf16_divider (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [15:0] a,    // BF16: 1s, 8e, 7m
    input  wire [15:0] b,    // BF16: 1s, 8e, 7m
    output reg  [15:0] result,
    output reg  error,
    output reg  done
);
    reg [2:0] state;
    localparam IDLE=3'd0, DECODE=3'd1, DIV=3'd2, NORM=3'd3, PACK=3'd4, OUTPUT=3'd5;

    // Decoded
    reg a_sign, b_sign;
    reg [7:0] a_exp, b_exp;
    reg [7:0] a_mant_full, b_mant_full; // 1.xxx => 8 bits
    reg a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;

    // Division intermediates
    reg result_sign;
    reg signed [9:0] result_exp;
    reg [15:0] div_rem;
    reg [15:0] div_quo;
    reg [7:0]  numerator;
    reg [7:0]  denominator;
    reg [4:0]  bit_cnt;

    // Normalize
    reg [7:0] norm_mant_full;
    reg [7:0] norm_exp_adj;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state  <= IDLE;
            result <= 16'h0000;
            error  <= 0;
            done   <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    error <= 0;
                    if (start) state <= DECODE;
                end

                DECODE: begin
                    a_sign <= a[15]; b_sign <= b[15];
                    a_exp  <= a[14:7]; b_exp <= b[14:7];
                    a_mant_full <= (a[14:7]==0) ? {1'b0, a[6:0]} : {1'b1, a[6:0]};
                    b_mant_full <= (b[14:7]==0) ? {1'b0, b[6:0]} : {1'b1, b[6:0]};
                    a_is_zero <= (a[14:7]==0) && (a[6:0]==0);
                    b_is_zero <= (b[14:7]==0) && (b[6:0]==0);
                    a_is_inf  <= (a[14:7]==8'hFF) && (a[6:0]==0);
                    b_is_inf  <= (b[14:7]==8'hFF) && (b[6:0]==0);
                    a_is_nan  <= (a[14:7]==8'hFF) && (a[6:0]!=0);
                    b_is_nan  <= (b[14:7]==8'hFF) && (b[6:0]!=0);
                    state <= DIV;
                end

                DIV: begin
                    // Special cases
                    if (a_is_nan || b_is_nan || (a_is_inf && b_is_inf) || (a_is_zero && b_is_zero)) begin
                        result <= 16'hFFC0; error <= 1; state <= OUTPUT;
                    end else if (b_is_zero) begin
                        result <= {a_sign^b_sign, 8'hFF, 7'h00}; error <= 1; state <= OUTPUT; // Inf
                    end else if (a_is_zero) begin
                        result <= {a_sign^b_sign, 8'h00, 7'h00}; state <= OUTPUT;
                    end else if (a_is_inf || b_is_inf) begin
                        if (a_is_inf && !b_is_inf) begin
                            result <= {a_sign^b_sign, 8'hFF, 7'h00}; state <= OUTPUT;
                        end else if (!a_is_inf && b_is_inf) begin
                            result <= {a_sign^b_sign, 8'h00, 7'h00}; state <= OUTPUT;
                        end else begin
                            result <= 16'hFFC0; error <= 1; state <= OUTPUT;
                        end
                    end else begin
                        // Regular path
                        result_sign <= a_sign ^ b_sign;
                        result_exp  <= $signed({2'b0,a_exp}) - $signed({2'b0,b_exp}) + 10'sd127;
                        // Restore division: (a_mant_full << 8) / b_mant_full -> 16-bit quotient
                        div_rem <= 0;
                        div_quo <= 0;
                        numerator   <= a_mant_full;
                        denominator <= b_mant_full;
                        bit_cnt <= 5'd16;
                        state <= NORM; // we'll do division in-line below
                        // Perform restoring division combinationally over 16 cycles
                    end
                end

                NORM: begin
                    if (bit_cnt != 0) begin
                        div_rem   <= {div_rem[14:0], numerator[7]} - {8'b0, denominator};
                        numerator <= {numerator[6:0], 1'b0};
                        if ({div_rem[14:0], numerator[7]} >= {8'b0, denominator})
                            div_quo <= {div_quo[14:0], 1'b1};
                        else begin
                            div_quo <= {div_quo[14:0], 1'b0};
                            div_rem <= {div_rem[14:0], numerator[7]}; // restore
                        end
                        bit_cnt <= bit_cnt - 1'b1;
                    end else begin
                        // div_quo holds 16-bit quotient ~ [1.x, 2.x) expected
                        if (div_quo[15]) begin
                            norm_mant_full <= div_quo[15:8];      // 1.xxx
                            norm_exp_adj   <= 0;
                        end else begin
                            norm_mant_full <= div_quo[14:7];      // shift left 1
                            norm_exp_adj   <= -1;
                        end
                        result_exp <= result_exp + $signed({2'b0, norm_exp_adj});
                        state <= PACK;
                    end
                end

                PACK: begin
                    // Overflow / underflow
                    if (result_exp >= 10'sd255) begin
                        result <= {result_sign, 8'hFF, 7'h00};
                        error  <= 1;
                    end else if (result_exp <= 0) begin
                        result <= {result_sign, 8'h00, 7'h00}; // underflow to zero
                    end else begin
                        result <= {result_sign, result_exp[7:0], norm_mant_full[6:0]};
                    end
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule