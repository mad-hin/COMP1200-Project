`timescale 1ns / 1ps
`include "define.vh"
// TODO fix the loop order problem
module display_controller(
    input wire clk,
    input wire rst,
    input wire [`INPUTOUTBIT-1:0] result, // BF16
    input wire error,
    input wire start, // Active high signal indicating result is ready
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg  [15:0] led,
    output reg  dp
);
    // ---------------- BF16 decode to signed Q16.16 ----------------
    wire        sign_bit  = result[15];
    wire [7:0]  exp_field = result[14:7];
    wire [6:0]  man_field = result[6:0]; 

    // Build unsigned magnitude: 1.mantissa aligned to bit 16 (Q16.16)
    wire [23:0] sig_q = {7'b0, 1'b1, man_field, 9'b0}; 

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
                default: val_mag_q = {24'd0, sig_q} << 16; // clamp
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
                default: val_mag_q = 48'd0; // underflow
            endcase
        end
    end

    // Apply sign
    wire signed [47:0] val_q_signed = sign_bit ? -$signed({1'b0,val_mag_q[46:0]}) 
                                               : $signed({1'b0,val_mag_q[46:0]});

    // Absolute value for display
    wire [47:0] val_abs = sign_bit ? (~val_q_signed + 1'b1) : val_q_signed;
    
    // ---------------- PIPELINE STAGES ----------------
    // Break the critical path by registering intermediate results
    
    // Stage 1: Register the absolute value and sign
    reg [47:0] val_abs_r;
    reg sign_bit_r;
    always @(posedge clk) begin
        val_abs_r <= val_abs;
        sign_bit_r <= sign_bit;
    end

    // Stage 2: Perform Multiplication and Integer Extraction
    // This isolates the heavy multiplier (16x27 bits) in its own clock cycle
    // FANOUT REDUCTION: These registers drive many division/comparison operations
    (* max_fanout = 32 *) reg [31:0] abs_int_r;
    (* max_fanout = 32 *) reg [26:0] abs_frac_val_r;
    
    always @(posedge clk) begin
        abs_int_r <= val_abs_r[47:16];
        // Multiply by 100,000,000 and shift right 16
        abs_frac_val_r <= (val_abs_r[15:0] * 64'd100000000) >> 16;
    end

    // ---------------- Stage 3: Decimal Digit Extraction (PIPELINED) --------------------
    // CRITICAL: Division operations create 52 logic levels! Must pipeline.
    // Register the extracted digits to break the combinational path.
    // Apply max_fanout to force register replication
    
    (* max_fanout = 16 *) reg [3:0] d4_r, d3_r, d2_r, d1_r, d0_r;
    (* max_fanout = 16 *) reg [3:0] f7_r, f6_r, f5_r, f4_r, f3_r, f2_r, f1_r, f0_r;
    reg [2:0] int_len_r;
    (* max_fanout = 32 *) reg has_sign_r, has_frac_r;
    
    always @(posedge clk) begin
        // Integer digits
        d4_r <= (abs_int_r / 10000) % 10;
        d3_r <= (abs_int_r / 1000 ) % 10;
        d2_r <= (abs_int_r / 100  ) % 10;
        d1_r <= (abs_int_r / 10   ) % 10;
        d0_r <=  abs_int_r % 10;
        
        // Fraction digits
        f7_r <= (abs_frac_val_r / 10000000) % 10;
        f6_r <= (abs_frac_val_r / 1000000) % 10;
        f5_r <= (abs_frac_val_r / 100000) % 10;
        f4_r <= (abs_frac_val_r / 10000) % 10;
        f3_r <= (abs_frac_val_r / 1000) % 10;
        f2_r <= (abs_frac_val_r / 100) % 10;
        f1_r <= (abs_frac_val_r / 10) % 10;
        f0_r <=  abs_frac_val_r % 10;
        
        // Control signals
        int_len_r <= (abs_int_r >= 10000) ? 3'd5 :
                     (abs_int_r >= 1000 ) ? 3'd4 :
                     (abs_int_r >= 100  ) ? 3'd3 :
                     (abs_int_r >= 10   ) ? 3'd2 : 3'd1;
        has_sign_r <= sign_bit_r;
        has_frac_r <= (abs_frac_val_r != 0);
    end
    
    // Construct stream of symbols: [Sign] [Int Digits] [Frac Digits]
    // Max symbols: 1 (sign) + 5 (int) + 8 (frac) = 14. We use array of 12 (enough for most cases).
    // NOW USES REGISTERED DIGITS (d4_r, d3_r, ..., f0_r, int_len_r, has_sign_r, has_frac_r)
    
    reg [3:0] sym [0:11];
    reg [11:0] dp_mask; // 1 where DP should be
    
    integer i;
    always @* begin
        // Clear
        for(i=0; i<12; i=i+1) sym[i] = 4'd11; // blank
        dp_mask = 12'b0;
        
        i = 0;
        
        // 1. Sign
        if (has_sign_r) begin
            sym[i] = 4'd10; // '-'
            i = i + 1;
        end
        
        // 2. Integer digits (MSB first) - use REGISTERED values
        if (int_len_r >= 5) begin sym[i] = d4_r; i=i+1; end
        if (int_len_r >= 4) begin sym[i] = d3_r; i=i+1; end
        if (int_len_r >= 3) begin sym[i] = d2_r; i=i+1; end
        if (int_len_r >= 2) begin sym[i] = d1_r; i=i+1; end
        sym[i] = d0_r; 
        
        // Decimal point goes after this digit (d0)
        if (has_frac_r) dp_mask[i] = 1'b1;
        i = i + 1;
        
        // 3. Fraction digits (up to 8) - use REGISTERED values
        if (has_frac_r && i < 12) begin sym[i] = f7_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f6_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f5_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f4_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f3_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f2_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f1_r; i=i+1; end
        if (has_frac_r && i < 12) begin sym[i] = f0_r; i=i+1; end
    end

    // ---------------- Windowing ----------------
    wire [3:0] used_syms = i; 
    wire [1:0] num_windows = (used_syms > 8) ? 2'd3 :
                             (used_syms > 4) ? 2'd2 : 2'd1;

    // Slow timer for window scrolling (approx 0.7s at 100MHz)
    reg [26:0] scroll_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) scroll_cnt <= 27'd1; // Start at 1 to avoid immediate tick
        else if (start) scroll_cnt <= scroll_cnt + 1;
        else scroll_cnt <= 27'd1;
    end
    wire scroll_tick = (scroll_cnt == 27'd0); // Tick on overflow/wrap

    reg [1:0] win_idx;
    always @(posedge clk or posedge rst) begin
        if (rst) win_idx <= 2'd0;
        else if (start && scroll_tick) begin
             win_idx <= (win_idx >= num_windows-1) ? 2'd0 : win_idx + 1'b1;
        end
    end

    // pick symbols for current window
    reg [3:0] d3_sel,d2_sel,d1_sel,d0_sel;
    reg dp3_sel,dp2_sel,dp1_sel,dp0_sel; // active-low
    
    always @* begin
        d3_sel=4'd11; d2_sel=4'd11; d1_sel=4'd11; d0_sel=4'd11;
        dp3_sel=1'b1; dp2_sel=1'b1; dp1_sel=1'b1; dp0_sel=1'b1;
        
        if (error) begin
            d3_sel=4'd14; d2_sel=4'd15; d1_sel=4'd15; d0_sel=4'd11; // "Err "
        end else begin
            if (win_idx == 0) begin
                d3_sel = sym[0]; dp3_sel = ~dp_mask[0];
                d2_sel = sym[1]; dp2_sel = ~dp_mask[1];
                d1_sel = sym[2]; dp1_sel = ~dp_mask[2];
                d0_sel = sym[3]; dp0_sel = ~dp_mask[3];
            end else if (win_idx == 1) begin
                d3_sel = sym[4]; dp3_sel = ~dp_mask[4];
                d2_sel = sym[5]; dp2_sel = ~dp_mask[5];
                d1_sel = sym[6]; dp1_sel = ~dp_mask[6];
                d0_sel = sym[7]; dp0_sel = ~dp_mask[7];
            end else begin // win_idx == 2
                d3_sel = sym[8]; dp3_sel = ~dp_mask[8];
                d2_sel = sym[9]; dp2_sel = ~dp_mask[9];
                d1_sel = sym[10]; dp1_sel = ~dp_mask[10];
                d0_sel = sym[11]; dp0_sel = ~dp_mask[11];
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

    // CRITICAL TIMING FIX: Add output register stage to break seg/an/dp path
    // Paths were -21ns due to combinational segment encoding. Register the outputs.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seg <= 7'b1111111;
            an <= 4'b1111;
            dp <= 1'b1;
        end else begin
            case (mux_sel)
                2'd0: begin an <= 4'b1110; seg <= seg_decode(d0_sel); dp <= dp0_sel; end
                2'd1: begin an <= 4'b1101; seg <= seg_decode(d1_sel); dp <= dp1_sel; end
                2'd2: begin an <= 4'b1011; seg <= seg_decode(d2_sel); dp <= dp2_sel; end
                default: begin an <= 4'b0111; seg <= seg_decode(d3_sel); dp <= dp3_sel; end
            endcase
        end
    end

    // ---------------- LED window indicator (REGISTERED) ----------------
    // CRITICAL: LED output was combinational on int_len_r (41 fanout).
    // Register to break the path and add 1 cycle latency (acceptable for display).
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led <= 16'b0;
        end else begin
            led <= 16'b0;
            if (error) led[2:0] <= 3'b000;
            else if (num_windows==2'd1) led[2:0] <= 3'b000;
            else if (num_windows==2'd2) led[2:0] <= (win_idx==0) ? 3'b001 : 3'b000;
            else led[2:0] <= (win_idx==0) ? 3'b001 : 
                             (win_idx==1) ? 3'b010 : 3'b000; // 001, 010, 000 for 3 windows
        end
    end
endmodule
