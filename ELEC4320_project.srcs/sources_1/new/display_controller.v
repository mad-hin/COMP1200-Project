`timescale 1ns / 1ps
`include "define.vh"
module display_controller #(
    parameter integer REFRESH_BITS   = 16,   // refresh for digit scan
    parameter integer PAGE_BITS      = 26    // page duration
)(
    input wire clk,
    input wire rst,
    input wire [`INPUTOUTBIT-1:0] result, // IEEE 754 single precision
    input wire error,
    input wire start,
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg  [15:0] led,
    output reg  dp
);

    // ----------------------------------------------------------------
    // Constants / helpers
    // ----------------------------------------------------------------
    localparam integer SCALE = 100000000; // 8 fractional digits (max 99,999,999)

    // Binary to BCD (8 digits) via double-dabble for 27-bit input
    function automatic [31:0] b2bcd8;
        input [26:0] bin; // supports up to 99,999,999
        integer i;
        reg [31:0] bcd; // 8 digits, [31:28] is MSD
        begin
            bcd = 32'd0;
            for (i = 26; i >= 0; i = i - 1) begin
                // add 3 to digits >=5
                if (bcd[31:28] >= 5) bcd[31:28] = bcd[31:28] + 4'd3;
                if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 4'd3;
                if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 4'd3;
                if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 4'd3;
                if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 4'd3;
                if (bcd[11:8]  >= 5) bcd[11:8]  = bcd[11:8]  + 4'd3;
                if (bcd[7:4]   >= 5) bcd[7:4]   = bcd[7:4]   + 4'd3;
                if (bcd[3:0]   >= 5) bcd[3:0]   = bcd[3:0]   + 4'd3;
                // shift left and bring in next bit
                bcd = {bcd[30:0], bin[i]};
            end
            b2bcd8 = bcd;
        end
    endfunction

    function integer dec_digits;
        input [63:0] v;
        integer k;
        reg   [63:0] t;
        begin
            t = v;
            dec_digits = 1;
            for (k = 0; k < 19; k = k + 1) begin
                if (t >= 10) begin
                    t = t / 10;
                    dec_digits = dec_digits + 1;
                end
            end
        end
    endfunction

    function [6:0] seg_encode;
        input [3:0] val;
        begin
            case (val)
                4'h0: seg_encode = 7'b1000000;
                4'h1: seg_encode = 7'b1111001;
                4'h2: seg_encode = 7'b0100100;
                4'h3: seg_encode = 7'b0110000;
                4'h4: seg_encode = 7'b0011001;
                4'h5: seg_encode = 7'b0010010;
                4'h6: seg_encode = 7'b0000010;
                4'h7: seg_encode = 7'b1111000;
                4'h8: seg_encode = 7'b0000000;
                4'h9: seg_encode = 7'b0010000;
                4'hA: seg_encode = 7'b0111111; // '-'
                4'hB: seg_encode = 7'b0000110; // 'E'
                4'hC: seg_encode = 7'b0101111; // 'r'
                default: seg_encode = 7'b1111111; // blank
            endcase
        end
    endfunction

    // ----------------------------------------------------------------
    // IEEE-754 unpack
    // ----------------------------------------------------------------
    reg        sign_bit;
    reg [7:0]  exp_bits;
    reg [22:0] frac_bits;
    reg signed [9:0]  exp_unbias;
    reg [47:0] mantissa_ext;

    reg signed [63:0] int_part_abs;
    reg        [63:0] frac_scaled_abs;

    integer shift_amt;
    reg [63:0] rem_bits;

    always @* begin
        sign_bit  = result[`INPUTOUTBIT-1];
        exp_bits  = result[`INPUTOUTBIT-2 -: 8];
        frac_bits = result[22:0];

        if (exp_bits == 8'd0) begin
            mantissa_ext = {1'b0, frac_bits}; // subnormal
            exp_unbias   = -126;
        end else begin
            mantissa_ext = {1'b1, frac_bits}; // normalized (24 bits)
            exp_unbias   = exp_bits - 127;
        end

        int_part_abs    = 0;
        frac_scaled_abs = 0;
        shift_amt       = 0;
        rem_bits        = 0;

        if (exp_unbias >= 23) begin
            int_part_abs    = mantissa_ext <<< (exp_unbias - 23);
            frac_scaled_abs = 0;
        end else begin
            shift_amt = 23 - exp_unbias;
            if (shift_amt >= 63) begin
                int_part_abs    = 0;
                frac_scaled_abs = 0;
            end else begin
                int_part_abs = mantissa_ext >> shift_amt;
                rem_bits     = mantissa_ext & ((64'd1 << shift_amt) - 1);
                frac_scaled_abs = (rem_bits * SCALE) >> shift_amt; // truncate
            end
        end
    end

    // Signed versions
    wire signed [63:0] int_part  = sign_bit ? -int_part_abs  : int_part_abs;
    wire signed [63:0] frac_part = sign_bit ? -$signed({1'b0, frac_scaled_abs}) : $signed({1'b0, frac_scaled_abs});

    // ----------------------------------------------------------------
    // Character buffer (max 9 chars: sign + 8 significant digits)
    // ----------------------------------------------------------------
    reg [3:0] chars [0:8];
    integer   char_count;
    integer   dec_point_idx; // index of digit before '.', -1 if none

    reg [26:0] int_clip;
    reg [26:0] frac_clip;
    reg [31:0] int_bcd;
    reg [31:0] frac_bcd;
    integer    int_len;
    integer    frac_need;
    reg        sign_needed;
    integer    idx;

    always @* begin
        char_count    = 0;
        dec_point_idx = -1;
        // clear buffer
        for (idx = 0; idx < 9; idx = idx + 1)
            chars[idx] = 4'hF;

        if (error) begin
            chars[0]    = 4'hB; // E
            chars[1]    = 4'hC; // r
            chars[2]    = 4'hC; // r
            char_count  = 3;
            dec_point_idx = -1;
        end else if (start) begin
            // clip to 8 digits each
            int_clip  = (int_part_abs > 99_999_999)  ? 27'd99_999_999  : int_part_abs[26:0];
            frac_clip = (frac_scaled_abs > 99_999_999)? 27'd99_999_999 : frac_scaled_abs[26:0];

            int_bcd  = b2bcd8(int_clip);
            frac_bcd = b2bcd8(frac_clip);

            sign_needed = (int_part < 0) || (int_part == 0 && frac_part < 0);

            // integer length: find first non-zero digit in int_bcd[31:28] (MSD) down to [3:0]
            if      (int_bcd[31:28] != 0) int_len = 8;
            else if (int_bcd[27:24] != 0) int_len = 7;
            else if (int_bcd[23:20] != 0) int_len = 6;
            else if (int_bcd[19:16] != 0) int_len = 5;
            else if (int_bcd[15:12] != 0) int_len = 4;
            else if (int_bcd[11:8]  != 0) int_len = 3;
            else if (int_bcd[7:4]   != 0) int_len = 2;
            else if (int_bcd[3:0]   != 0) int_len = 1;
            else                          int_len = 1; // zero

            if (int_len >= 8)
                frac_need = 0;
            else
                frac_need = 8 - int_len;

            // sign
            if (sign_needed) begin
                chars[char_count] = 4'hA;
                char_count = char_count + 1;
            end

            // integer digits MSB-first from int_bcd
            // int_len tells how many digits to emit, starting at the correct MSB
            case (int_len)
                8: begin
                    chars[char_count] = int_bcd[31:28]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[27:24]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[23:20]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[19:16]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[15:12]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[11:8];  char_count = char_count + 1;
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                7: begin
                    chars[char_count] = int_bcd[27:24]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[23:20]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[19:16]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[15:12]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[11:8];  char_count = char_count + 1;
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                6: begin
                    chars[char_count] = int_bcd[23:20]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[19:16]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[15:12]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[11:8];  char_count = char_count + 1;
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                5: begin
                    chars[char_count] = int_bcd[19:16]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[15:12]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[11:8];  char_count = char_count + 1;
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                4: begin
                    chars[char_count] = int_bcd[15:12]; char_count = char_count + 1;
                    chars[char_count] = int_bcd[11:8];  char_count = char_count + 1;
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                3: begin
                    chars[char_count] = int_bcd[11:8];  char_count = char_count + 1;
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                2: begin
                    chars[char_count] = int_bcd[7:4];   char_count = char_count + 1;
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1;
                end
                default: begin
                    chars[char_count] = int_bcd[3:0];   char_count = char_count + 1; // len=1
                end
            endcase

            // fractional digits: take the top frac_need digits from frac_bcd MSB-first
            if (frac_need != 0) begin
                if (frac_need >= 1) begin chars[char_count] = frac_bcd[31:28]; char_count = char_count + 1; end
                if (frac_need >= 2) begin chars[char_count] = frac_bcd[27:24]; char_count = char_count + 1; end
                if (frac_need >= 3) begin chars[char_count] = frac_bcd[23:20]; char_count = char_count + 1; end
                if (frac_need >= 4) begin chars[char_count] = frac_bcd[19:16]; char_count = char_count + 1; end
                if (frac_need >= 5) begin chars[char_count] = frac_bcd[15:12]; char_count = char_count + 1; end
                if (frac_need >= 6) begin chars[char_count] = frac_bcd[11:8];  char_count = char_count + 1; end
                if (frac_need >= 7) begin chars[char_count] = frac_bcd[7:4];   char_count = char_count + 1; end
                if (frac_need >= 8) begin chars[char_count] = frac_bcd[3:0];   char_count = char_count + 1; end
                dec_point_idx = (sign_needed ? int_len : int_len - 1);
            end else begin
                dec_point_idx = -1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Timing: digit refresh and page switching
    // ----------------------------------------------------------------
    reg [REFRESH_BITS-1:0] refresh_cnt;
    reg [PAGE_BITS-1:0]    page_cnt;
    reg [1:0]              active_digit;
    reg [2:0]              page_idx;
    reg [2:0]              page_max;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            refresh_cnt  <= 0;
            active_digit <= 0;
        end else if (start) begin
            refresh_cnt  <= refresh_cnt + 1'b1;
            active_digit <= refresh_cnt[REFRESH_BITS-1:REFRESH_BITS-2];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            page_cnt <= 0;
            page_idx <= 0;
        end else if (start) begin
            page_cnt <= page_cnt + 1'b1;
            if (page_cnt[PAGE_BITS-1]) begin
                page_cnt <= 0;
                if (page_idx == page_max)
                    page_idx <= 0;
                else
                    page_idx <= page_idx + 1'b1;
            end
        end
    end

    always @* begin
        if (char_count <= 4)
            page_max = 0;
        else if (char_count <= 8)
            page_max = 1;
        else
            page_max = 2; // up to 9 chars
    end

    // ----------------------------------------------------------------
    // Drive 7-seg and dp
    // ----------------------------------------------------------------
    reg [3:0] current_char;
    reg       dp_on;
    integer   global_offset;
    integer   char_idx;

    always @* begin
        if (!start) begin
            an  = 4'b1111;
            seg = 7'b1111111;
            dp  = 1'b1;
        end else begin
            // default anodes high (off)
            an = 4'b1111;
            an[active_digit] = 1'b0;

            global_offset = page_idx * 4 + active_digit;
            if (global_offset >= char_count) begin
                current_char = 4'hF; // blank
                dp_on = 1'b0;
            end else begin
                char_idx = char_count - 1 - global_offset; // LSB-first paging
                current_char = chars[char_idx];
                dp_on = (dec_point_idx >= 0) && (char_idx == dec_point_idx);
            end

            seg = seg_encode(current_char);
            dp  = dp_on ? 1'b0 : 1'b1; // active low
        end
    end

    // ----------------------------------------------------------------
    // LED page indicator (LSBs)
    // ----------------------------------------------------------------
    always @* begin
        if (!start) begin
            led = 16'b0;
        end else begin
            led = 16'b0;
            led[2:0] = page_idx;
        end
    end

endmodule
