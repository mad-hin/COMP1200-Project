`timescale 1ns / 1ps
`include "define.vh"

module display_controller(
    input wire clk,
    input wire rst,
    input wire [`INPUTOUTBIT-1:0] result, // BF16
    input wire error,
    input wire start,
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg  [15:0] led,
    output reg  dp
);
    // ---------------- BF16 decode to signed Q16.16 ----------------
    wire        sign_bit  = result[15];
    wire [7:0]  exp_field = result[14:7];
    wire [6:0]  man_field = result[6:0]; 

    // Build unsigned magnitude: 1.mantissa in Q16.16 (24 bits keep margin)
    wire [23:0] sig_q = {1'b1, man_field, 16'd0}; // 1.M * 2^16

    wire signed [8:0] e_bias = {1'b0,exp_field} - 9'sd127;

    reg [47:0] val_mag_q; // unsigned magnitude Q16.16 after shift
    always @* begin
        if (e_bias >= 0) begin
            case (e_bias[4:0]) // 0..31
                5'd0 : val_mag_q = {24'd0, sig_q};
                5'd1 : val_mag_q = {24'd0, sig_q} << 1;
                5'd2 : val_mag_q = {24'd0, sig_q} << 2;
                5'd3 : val_mag_q = {24'd0, sig_q} << 3;
                5'd4 : val_mag_q = {24'd0, sig_q} << 4;
                5'd5 : val_mag_q = {24'd0, sig_q} << 5;
                5'd6 : val_mag_q = {24'd0, sig_q} << 6;
                5'd7 : val_mag_q = {24'd0, sig_q} << 7;
                5'd8 : val_mag_q = {24'd0, sig_q} << 8;
                5'd9 : val_mag_q = {24'd0, sig_q} << 9;
                5'd10: val_mag_q = {24'd0, sig_q} << 10;
                5'd11: val_mag_q = {24'd0, sig_q} << 11;
                5'd12: val_mag_q = {24'd0, sig_q} << 12;
                5'd13: val_mag_q = {24'd0, sig_q} << 13;
                5'd14: val_mag_q = {24'd0, sig_q} << 14;
                5'd15: val_mag_q = {24'd0, sig_q} << 15;
                5'd16: val_mag_q = {24'd0, sig_q} << 16;
                5'd17: val_mag_q = {24'd0, sig_q} << 17;
                5'd18: val_mag_q = {24'd0, sig_q} << 18;
                5'd19: val_mag_q = {24'd0, sig_q} << 19;
                5'd20: val_mag_q = {24'd0, sig_q} << 20;
                5'd21: val_mag_q = {24'd0, sig_q} << 21;
                5'd22: val_mag_q = {24'd0, sig_q} << 22;
                5'd23: val_mag_q = {24'd0, sig_q} << 23;
                5'd24: val_mag_q = {24'd0, sig_q} << 24;
                5'd25: val_mag_q = {24'd0, sig_q} << 25;
                5'd26: val_mag_q = {24'd0, sig_q} << 26;
                5'd27: val_mag_q = {24'd0, sig_q} << 27;
                5'd28: val_mag_q = {24'd0, sig_q} << 28;
                5'd29: val_mag_q = {24'd0, sig_q} << 29;
                5'd30: val_mag_q = {24'd0, sig_q} << 30;
                default: val_mag_q = {24'd0, sig_q} << 31;
            endcase
        end else begin
            case (-e_bias[4:0])
                5'd0 : val_mag_q = {24'd0, sig_q};
                5'd1 : val_mag_q = {24'd0, sig_q} >> 1;
                5'd2 : val_mag_q = {24'd0, sig_q} >> 2;
                5'd3 : val_mag_q = {24'd0, sig_q} >> 3;
                5'd4 : val_mag_q = {24'd0, sig_q} >> 4;
                5'd5 : val_mag_q = {24'd0, sig_q} >> 5;
                5'd6 : val_mag_q = {24'd0, sig_q} >> 6;
                5'd7 : val_mag_q = {24'd0, sig_q} >> 7;
                5'd8 : val_mag_q = {24'd0, sig_q} >> 8;
                5'd9 : val_mag_q = {24'd0, sig_q} >> 9;
                5'd10: val_mag_q = {24'd0, sig_q} >> 10;
                5'd11: val_mag_q = {24'd0, sig_q} >> 11;
                5'd12: val_mag_q = {24'd0, sig_q} >> 12;
                5'd13: val_mag_q = {24'd0, sig_q} >> 13;
                5'd14: val_mag_q = {24'd0, sig_q} >> 14;
                5'd15: val_mag_q = {24'd0, sig_q} >> 15;
                5'd16: val_mag_q = {24'd0, sig_q} >> 16;
                5'd17: val_mag_q = {24'd0, sig_q} >> 17;
                5'd18: val_mag_q = {24'd0, sig_q} >> 18;
                5'd19: val_mag_q = {24'd0, sig_q} >> 19;
                5'd20: val_mag_q = {24'd0, sig_q} >> 20;
                5'd21: val_mag_q = {24'd0, sig_q} >> 21;
                5'd22: val_mag_q = {24'd0, sig_q} >> 22;
                5'd23: val_mag_q = {24'd0, sig_q} >> 23;
                5'd24: val_mag_q = {24'd0, sig_q} >> 24;
                5'd25: val_mag_q = {24'd0, sig_q} >> 25;
                5'd26: val_mag_q = {24'd0, sig_q} >> 26;
                5'd27: val_mag_q = {24'd0, sig_q} >> 27;
                5'd28: val_mag_q = {24'd0, sig_q} >> 28;
                5'd29: val_mag_q = {24'd0, sig_q} >> 29;
                5'd30: val_mag_q = {24'd0, sig_q} >> 30;
                default: val_mag_q = 48'd0; // underflow
            endcase
        end
    end

    // Apply sign after shift
    wire signed [47:0] val_q_signed = sign_bit ? -$signed({1'b0,val_mag_q[46:0]}) 
                                               : $signed({1'b0,val_mag_q[46:0]});

    // integer part (truncate fraction)
    wire signed [31:0] val_int = val_q_signed[47:16];
    wire        val_sign = val_int[31];
    wire [31:0] abs_int  = val_sign ? (~val_int + 1'b1) : val_int;

    // --------------- Decimal digits (no loops) --------------------
    // up to 8 digits (most significant)
    wire [3:0] d7 = (abs_int / 32'd10000000) % 10;
    wire [3:0] d6 = (abs_int / 32'd1000000 ) % 10;
    wire [3:0] d5 = (abs_int / 32'd100000  ) % 10;
    wire [3:0] d4 = (abs_int / 32'd10000   ) % 10;
    wire [3:0] d3 = (abs_int / 32'd1000    ) % 10;
    wire [3:0] d2 = (abs_int / 32'd100     ) % 10;
    wire [3:0] d1 = (abs_int / 32'd10      ) % 10;
    wire [3:0] d0 =  abs_int % 10;

    wire [3:0] int_len = (abs_int >= 32'd10000000) ? 4'd8 :
                         (abs_int >= 32'd1000000 ) ? 4'd7 :
                         (abs_int >= 32'd100000  ) ? 4'd6 :
                         (abs_int >= 32'd10000   ) ? 4'd5 :
                         (abs_int >= 32'd1000    ) ? 4'd4 :
                         (abs_int >= 32'd100     ) ? 4'd3 :
                         (abs_int >= 32'd10      ) ? 4'd2 : 4'd1;

    wire has_sign = val_sign;
    wire [3:0] max_digits = has_sign ? 4'd7 : 4'd8; // digit slots (sign uses 1)
    wire use_trunc = (int_len > max_digits);

    // total symbols (including sign if any)
    wire [3:0] total_syms = use_trunc ? (max_digits + has_sign) : (int_len + has_sign);

    // Symbol codes (0-9 digits, 10 = '-', 11 = blank)
    wire [3:0] sym0 = has_sign ? 4'd10 : use_trunc ? d7 :
                      (int_len==8)? d7 :
                      (int_len==7)? d6 :
                      (int_len==6)? d5 :
                      (int_len==5)? d4 :
                      (int_len==4)? d3 :
                      (int_len==3)? d2 :
                      (int_len==2)? d1 : d0;

    wire [3:0] sym1 = has_sign ? (use_trunc ? d7 :
                          (int_len==8)? d7 :
                          (int_len==7)? d6 :
                          (int_len==6)? d5 :
                          (int_len==5)? d4 :
                          (int_len==4)? d3 :
                          (int_len==3)? d2 :
                          (int_len==2)? d1 : d0)
                       : (use_trunc ? d6 :
                          (int_len==8)? d6 :
                          (int_len==7)? d5 :
                          (int_len==6)? d4 :
                          (int_len==5)? d3 :
                          (int_len==4)? d2 :
                          (int_len==3)? d1 :
                          (int_len==2)? d0 : 4'd11);  // blank

    wire [3:0] sym2 = has_sign ? (use_trunc ? d6 :
                          (int_len==8)? d6 :
                          (int_len==7)? d5 :
                          (int_len==6)? d4 :
                          (int_len==5)? d3 :
                          (int_len==4)? d2 :
                          (int_len==3)? d1 :
                          (int_len==2)? d0 : 4'd11)
                       : (use_trunc ? d5 :
                          (int_len==8)? d5 :
                          (int_len==7)? d4 :
                          (int_len==6)? d3 :
                          (int_len==5)? d2 :
                          (int_len==4)? d1 :
                          (int_len==3)? d0 : 4'd11);

    wire [3:0] sym3 = has_sign ? (use_trunc ? d5 :
                          (int_len==8)? d5 :
                          (int_len==7)? d4 :
                          (int_len==6)? d3 :
                          (int_len==5)? d2 :
                          (int_len==4)? d1 :
                          (int_len==3)? d0 : 4'd11)
                       : (use_trunc ? d4 :
                          (int_len==8)? d4 :
                          (int_len==7)? d3 :
                          (int_len==6)? d2 :
                          (int_len==5)? d1 :
                          (int_len==4)? d0 : 4'd11);

    wire [3:0] sym4 = has_sign ? (use_trunc ? d4 :
                          (int_len==8)? d4 :
                          (int_len==7)? d3 :
                          (int_len==6)? d2 :
                          (int_len==5)? d1 :
                          (int_len==4)? d0 : 4'd11)
                       : (use_trunc ? d3 :
                          (int_len==8)? d3 :
                          (int_len==7)? d2 :
                          (int_len==6)? d1 :
                          (int_len==5)? d0 : 4'd11);

    wire [3:0] sym5 = has_sign ? (use_trunc ? d3 :
                          (int_len==8)? d3 :
                          (int_len==7)? d2 :
                          (int_len==6)? d1 :
                          (int_len==5)? d0 : 4'd11)
                       : (use_trunc ? d2 :
                          (int_len==8)? d2 :
                          (int_len==7)? d1 :
                          (int_len==6)? d0 : 4'd11);

    wire [3:0] sym6 = has_sign ? (use_trunc ? d2 :
                          (int_len==8)? d2 :
                          (int_len==7)? d1 :
                          (int_len==6)? d0 : 4'd11)
                       : (use_trunc ? d1 :
                          (int_len==8)? d1 :
                          (int_len==7)? d0 : 4'd11);

    wire [3:0] sym7 = has_sign ? (use_trunc ? d1 :
                          (int_len==8)? d1 :
                          (int_len==7)? d0 : 4'd11)
                       : (use_trunc ? d0 :
                          (int_len==8)? d0 : 4'd11);

    // DP mask (none for integer-only)
    wire [7:0] dp_mask = 8'b0;

    // ---------------- Windowing ----------------
    wire [1:0] num_windows = (total_syms > 4) ? 2'd2 : 2'd1;

    reg [1:0] win_idx;
    always @(posedge clk or posedge rst) begin
        if (rst) win_idx <= 2'd0;
        else if (start)  win_idx <= (win_idx == num_windows-1) ? 2'd0 : win_idx + 1'b1;
    end

    // pick symbols for current window (MS first)
    reg [3:0] d3_sel,d2_sel,d1_sel,d0_sel;
    reg dp3_sel,dp2_sel,dp1_sel,dp0_sel; // active-low
    always @* begin
        d3_sel=4'd0; d2_sel=4'd0; d1_sel=4'd0; d0_sel=4'd0;
        dp3_sel=1'b1; dp2_sel=1'b1; dp1_sel=1'b1; dp0_sel=1'b1;
        if (error) begin
            // Display "Err "
            d3_sel=4'd14; // E
            d2_sel=4'd15; // r
            d1_sel=4'd15; // r
            d0_sel=4'd11; // blank
        end else if (num_windows==2'd1) begin
            d3_sel=sym0; d2_sel=sym1; d1_sel=sym2; d0_sel=sym3;
            dp3_sel=~dp_mask[7]; dp2_sel=~dp_mask[6]; dp1_sel=~dp_mask[5]; dp0_sel=~dp_mask[4];
        end else begin
            if (win_idx==2'd0) begin
                d3_sel=sym0; d2_sel=sym1; d1_sel=sym2; d0_sel=sym3;
                dp3_sel=~dp_mask[7]; dp2_sel=~dp_mask[6]; dp1_sel=~dp_mask[5]; dp0_sel=~dp_mask[4];
            end else begin
                d3_sel=sym4; d2_sel=sym5; d1_sel=sym6; d0_sel=sym7;
                dp3_sel=~dp_mask[3]; dp2_sel=~dp_mask[2]; dp1_sel=~dp_mask[1]; dp0_sel=~dp_mask[0];
            end
        end
    end

    // ---------------- 7-seg encode ----------------
    function [6:0] seg_decode;
        input [3:0] code;
        begin
            case (code)
                4'd0: seg_decode = 7'b1000000;
                4'd1: seg_decode = 7'b1111001;
                4'd2: seg_decode = 7'b0100100;
                4'd3: seg_decode = 7'b0110000;
                4'd4: seg_decode = 7'b0011001;
                4'd5: seg_decode = 7'b0010010;
                4'd6: seg_decode = 7'b0000010;
                4'd7: seg_decode = 7'b1111000;
                4'd8: seg_decode = 7'b0000000;
                4'd9: seg_decode = 7'b0010000;
                4'd10: seg_decode = 7'b0111111; // '-'
                4'd11: seg_decode = 7'b1111111; // blank
                4'd14: seg_decode = 7'b0000110; // 'E'
                4'd15: seg_decode = 7'b0101111; // 'r'
                default: seg_decode = 7'b1111111;
            endcase
        end
    endfunction

    // ---------------- Multiplex scan ----------------
    reg [23:0] refresh_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) refresh_cnt <= 24'd0;
        else     refresh_cnt <= refresh_cnt + 1'b1;
    end
    wire [1:0] mux_sel = refresh_cnt[18:17];

    always @* begin
        case (mux_sel)
            2'd0: begin an=4'b1110; seg=seg_decode(d0_sel); dp=dp0_sel; end
            2'd1: begin an=4'b1101; seg=seg_decode(d1_sel); dp=dp1_sel; end
            2'd2: begin an=4'b1011; seg=seg_decode(d2_sel); dp=dp2_sel; end
            default: begin an=4'b0111; seg=seg_decode(d3_sel); dp=dp3_sel; end
        endcase
    end

    // ---------------- LED window indicator ----------------
    always @* begin
        led = 16'b0;
        if (error) led[2:0] = 3'b000;
        else if (num_windows==2'd1) led[2:0] = 3'b000;
        else led[2:0] = (win_idx==0) ? 3'b001 : 3'b000; // 001 then 000 as example
    end
endmodule
