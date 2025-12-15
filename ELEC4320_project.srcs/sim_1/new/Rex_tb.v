`timescale 1ns/1ps

// Note: Pure Verilog-2001 testbench with built-in BF16->real helper and self-check.
// Clock is 100 MHz (adjustable). 'start' is a single-cycle pulse.
module arctan_tb;
    // DUT ports
    reg  clk;
    reg  rst;
    reg  start;
    reg  signed [15:0] a;
    wire [15:0] result;
    wire error;
    wire done;

    // Statistics
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ========= Helper functions =========
    function real bf16_to_real;
        input [15:0] bf;
        reg sign;
        reg [7:0] exp;
        reg [6:0] mant;
        real frac;
        begin
            sign = bf[15];
            exp  = bf[14:7];
            mant = bf[6:0];
            if (exp == 0) begin
                // subnormal or zero
                frac = mant / 128.0;
                bf16_to_real = (sign ? -1.0 : 1.0) * frac * (2.0 ** (-126));
            end else if (exp == 8'hFF) begin
                bf16_to_real = 0.0/0.0; // NaN/Inf; simulation will print nan/inf
            end else begin
                frac = 1.0 + mant / 128.0;
                bf16_to_real = (sign ? -1.0 : 1.0) * frac * (2.0 ** (exp - 127));
            end
        end
    endfunction

    function real rabs;
        input real v;
        begin
            rabs = (v < 0.0) ? -v : v;
        end
    endfunction

    task do_test;
        input  signed [15:0] slope;
        input  real exp_deg;
        real got_deg;
        real err_deg;
        begin
            // Apply input and a single-cycle start pulse (synchronized to clock)
            @(negedge clk);
            a     <= slope;
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;

            // Wait for done
            wait (done === 1'b1);
            got_deg = bf16_to_real(result);
            err_deg = got_deg - exp_deg;

            if (rabs(err_deg) <= 0.6) begin
                pass_cnt = pass_cnt + 1;
                $display("[%0t] PASS  a=%0d  exp=%.4f  got=%.4f  err=%.4f",
                         $time, slope, exp_deg, got_deg, err_deg);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[%0t] FAIL  a=%0d  exp=%.4f  got=%.4f  err=%.4f",
                         $time, slope, exp_deg, got_deg, err_deg);
            end

            // Wait for done to deassert, return to IDLE
            @(negedge clk);
        end
    endtask

    // ========= DUT instantiation =========
    arctan dut (
        .clk   (clk),
        .rst   (rst),
        .start (start),
        .a     (a),
        .result(result),
        .error (error),
        .done  (done)
    );

    // ========= Clock and reset =========
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz
    end

    initial begin
        rst   = 1'b1;
        start = 1'b0;
        a     = 16'sd0;
        #50;
        rst   = 1'b0;
    end

    // ========= Stimulus sequence =========
    initial begin
        // Wait for reset release
        @(negedge rst);

        // Special-value checks
        do_test(16'sd0   ,  0.0     );
        do_test(16'sd1   , 45.0     );
        do_test(-16'sd1  , -45.0    );

        // General tests (expected angles in degrees)
        do_test(16'sd2   , 63.4349  );
        do_test(-16'sd2  , -63.4349 );
        do_test(16'sd10  , 84.2894  );
        do_test(-16'sd10 , -84.2894 );
        do_test(16'sd123 , 89.5350  );
        do_test(-16'sd456, -89.8750 );
        do_test(16'sd999 , 89.9427  );

        // Report summary
        $display("======== Summary ========");
        $display("PASS: %0d", pass_cnt);
        $display("FAIL: %0d", fail_cnt);
        $finish;
    end
endmodule