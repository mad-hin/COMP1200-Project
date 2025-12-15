`timescale 1ns/1ps

// 说明：纯 Verilog-2001，自带 BF16->real 辅助函数与自检。
// 时钟 100 MHz，可根据需要调整。start 为单拍脉冲。
module arctan_tb;
    // DUT 端口
    reg  clk;
    reg  rst;
    reg  start;
    reg  signed [15:0] a;
    wire [15:0] result;
    wire error;
    wire done;

    // 统计
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ========= 辅助函数 =========
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
                // subnormal 或 0
                frac = mant / 128.0;
                bf16_to_real = (sign ? -1.0 : 1.0) * frac * (2.0 ** (-126));
            end else if (exp == 8'hFF) begin
                bf16_to_real = 0.0/0.0; // NaN/Inf，仿真打印会显示 nan/inf
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
            // 施加输入与 start 脉冲（同步上升沿）
            @(negedge clk);
            a     <= slope;
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;

            // 等待 done
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

            // 等待 done 拉低，回到 IDLE
            @(negedge clk);
        end
    endtask

    // ========= DUT 实例 =========
    arctan dut (
        .clk   (clk),
        .rst   (rst),
        .start (start),
        .a     (a),
        .result(result),
        .error (error),
        .done  (done)
    );

    // ========= 时钟与复位 =========
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

    // ========= 激励序列 =========
    initial begin
        // 等待复位释放
        @(negedge rst);

        // 特殊值检查
        do_test(16'sd0   ,  0.0     );
        do_test(16'sd1   , 45.0     );
        do_test(-16'sd1  , -45.0    );

        // 常规测试（预期角度为度）
        do_test(16'sd2   , 63.4349  );
        do_test(-16'sd2  , -63.4349 );
        do_test(16'sd10  , 84.2894  );
        do_test(-16'sd10 , -84.2894 );
        do_test(16'sd123 , 89.5350  );
        do_test(-16'sd456, -89.8750 );
        do_test(16'sd999 , 89.9427  );

        // 统计结果
        $display("======== Summary ========");
        $display("PASS: %0d", pass_cnt);
        $display("FAIL: %0d", fail_cnt);
        $finish;
    end
endmodule