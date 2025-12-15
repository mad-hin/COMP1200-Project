`timescale 1ns/1ps

module bf16_divider_tb;
    localparam real    CLK_PERIOD = 3;
    localparam integer VEC_NUM    = 9;

    reg clk = 0;
    reg rst = 1;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // DUT ports
    reg  start = 0;
    reg  [15:0] a_in = 16'h0;
    reg  [15:0] b_in = 16'h0;
    wire [15:0] result;
    wire error;
    wire done;

    bf16_divider dut (
        .clk   (clk),
        .rst   (rst),
        .start (start),
        .a     (a_in),
        .b     (b_in),
        .result(result),
        .error (error),
        .done  (done)
    );

    // Helpers ------------------------------------------------------------
    // BF16 encode from real (简化截断，不做舍入)
    function [15:0] real_to_bf16;
        input real val;
        reg [63:0] bits;
        reg sign;
        reg [10:0] exp11;
        reg [51:0] frac;
        reg [7:0]  exp8;
        reg [6:0]  mant7;
    begin
        bits  = $realtobits(val);
        sign  = bits[63];
        exp11 = bits[62:52];
        frac  = bits[51:0];
        if (exp11 == 11'h7FF) begin
            // Inf / NaN
            if (frac != 0)
                real_to_bf16 = 16'hFFC0; // NaN payload
            else
                real_to_bf16 = {sign, 8'hFF, 7'h00};
        end else if (exp11 == 0) begin
            // subnormal or zero -> 0
            real_to_bf16 = {sign, 8'h00, 7'h00};
        end else begin
            exp8  = exp11 - 11'd1023 + 8'd127;
            mant7 = frac[51:45]; // 截断
            real_to_bf16 = {sign, exp8, mant7};
        end
    end
    endfunction

    // BF16 decode to real
    function real bf16_to_real;
        input [15:0] bf;
        reg sign;
        reg [7:0] exp8;
        reg [6:0] mant7;
        reg [63:0] bits;
    begin
        sign = bf[15];
        exp8 = bf[14:7];
        mant7= bf[6:0];
        if (exp8 == 8'hFF) begin
            if (mant7 != 0)
                bf16_to_real = 0.0/0.0; // NaN
            else
                bf16_to_real = sign ? -1.0/0.0 : 1.0/0.0;
        end else if (exp8 == 8'h00) begin
            if (mant7 == 0)
                bf16_to_real = 0.0;
            else begin
                bits = {sign, 11'd1023-126, mant7, 45'd0}; // 2^-126 对应 exp=1（BF16），映射到 double
                bf16_to_real = $bitstoreal(bits);
            end
        end else begin
            bits = {sign, exp8-8'd127+11'd1023, mant7, 45'd0};
            bf16_to_real = $bitstoreal(bits);
        end
    end
    endfunction

    // kinds: 0=normal/finite, 1=+/-Inf, 2=Zero, 3=NaN
    reg [1:0] expect_kind [0:VEC_NUM-1];
    real      expect_real [0:VEC_NUM-1];
    reg [15:0] ain_vec    [0:VEC_NUM-1];
    reg [15:0] bin_vec    [0:VEC_NUM-1];
    reg [15:0] expect_bf16[0:VEC_NUM-1]; // 仅用于特殊值判断

    // Apply one transaction
    task automatic apply_start(input [15:0] a, input [15:0] b);
    begin
        @(negedge clk);
        a_in  <= a;
        b_in  <= b;
        start <= 1'b1;
        @(negedge clk);
        start <= 1'b0;
    end
    endtask

    // Check result
    task automatic check_result(input integer idx);
        real got_real;
        real diff;
        reg  is_nan, is_inf, is_zero;
    begin
        got_real = bf16_to_real(result);
        is_nan   = (result[14:7] == 8'hFF) && (result[6:0] != 0);
        is_inf   = (result[14:7] == 8'hFF) && (result[6:0] == 0);
        is_zero  = (result[14:7] == 8'h00) && (result[6:0] == 0);

        case (expect_kind[idx])
            3: begin // NaN
                if (is_nan)
                    $display("[%0t] VEC%0d PASS (NaN)", $time, idx);
                else
                    $display("[%0t] VEC%0d FAIL exp=NaN got=0x%h", $time, idx, result);
            end
            1: begin // Inf
                if (is_inf && (result[15] == expect_bf16[idx][15]))
                    $display("[%0t] VEC%0d PASS (Inf)", $time, idx);
                else
                    $display("[%0t] VEC%0d FAIL exp=Inf got=0x%h", $time, idx, result);
            end
            2: begin // Zero
                if (is_zero && (result[15] == expect_bf16[idx][15]))
                    $display("[%0t] VEC%0d PASS (Zero)", $time, idx);
                else
                    $display("[%0t] VEC%0d FAIL exp=Zero got=0x%h", $time, idx, result);
            end
            default: begin // finite compare with tolerance
                diff = got_real - expect_real[idx];
                if (diff < 0) diff = -diff;
                if (diff < 1e-3)
                    $display("[%0t] VEC%0d PASS exp=%f got=%f", $time, idx, expect_real[idx], got_real);
                else
                    $display("[%0t] VEC%0d FAIL exp=%f got=%f (bf16=0x%h)", $time, idx, expect_real[idx], got_real, result);
            end
        endcase
    end
    endtask

    integer i;
    initial begin
        // Test vectors:
        // 0: 1 / 2 = 0.5
        // 1: 2 / 1 = 2
        // 2: -3 / 1.5 = -2
        // 3: 0 / 1 = 0
        // 4: 1 / 0 -> +Inf (error=1)
        // 5: Inf / 2 -> +Inf
        // 6: 2 / Inf -> +0
        // 7: NaN / 1 -> NaN
        // 8: (1e-5) / (1e5) -> ~1e-10 -> underflow to 0

        // prepare inputs
        ain_vec[0] = real_to_bf16(1.0);      bin_vec[0] = real_to_bf16(2.0);      expect_kind[0]=0; expect_real[0]=0.5;
        ain_vec[1] = real_to_bf16(2.0);      bin_vec[1] = real_to_bf16(1.0);      expect_kind[1]=0; expect_real[1]=2.0;
        ain_vec[2] = real_to_bf16(-3.0);     bin_vec[2] = real_to_bf16(1.5);      expect_kind[2]=0; expect_real[2]=-2.0;
        ain_vec[3] = real_to_bf16(0.0);      bin_vec[3] = real_to_bf16(1.0);      expect_kind[3]=2; expect_bf16[3]=real_to_bf16(0.0);
        ain_vec[4] = real_to_bf16(1.0);      bin_vec[4] = real_to_bf16(0.0);      expect_kind[4]=1; expect_bf16[4]={1'b0,8'hFF,7'h00};
        ain_vec[5] = {1'b0,8'hFF,7'h00};     bin_vec[5] = real_to_bf16(2.0);      expect_kind[5]=1; expect_bf16[5]={1'b0,8'hFF,7'h00};
        ain_vec[6] = real_to_bf16(2.0);      bin_vec[6] = {1'b0,8'hFF,7'h00};     expect_kind[6]=2; expect_bf16[6]=real_to_bf16(0.0);
        ain_vec[7] = 16'hFFC0;               bin_vec[7] = real_to_bf16(1.0);      expect_kind[7]=3;
        ain_vec[8] = real_to_bf16(1.0e-5);   bin_vec[8] = real_to_bf16(1.0e5);    expect_kind[8]=2; expect_bf16[8]=real_to_bf16(0.0);

        $dumpfile("bf16_divider_tb.vcd");
        $dumpvars(0, bf16_divider_tb);

        // reset
        repeat (4) @(negedge clk);
        rst <= 0;

        for (i=0; i<VEC_NUM; i=i+1) begin
            apply_start(ain_vec[i], bin_vec[i]);
            wait(done);
            @(posedge clk);
            check_result(i);
        end

        $display("All vectors done.");
        #(10*CLK_PERIOD);
        $finish;
    end
endmodule