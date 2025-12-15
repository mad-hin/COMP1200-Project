`timescale 1ns / 1ps
`include "define.vh"

module arctan_tb;
    reg clk, rst, start;
    reg signed [`INPUTOUTBIT-1:0] a;
    wire [`INPUTOUTBIT-1:0] result;
    wire done, error;

    arctan uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
        .result(result),
        .error(error),
        .done(done)
    );

    initial begin clk = 0; forever #1.67 clk = ~clk; end

    initial begin
        rst = 1; start = 0; a = 0;
        #100; rst = 0; #20;
        run_test(16'sd0);
        run_test(16'sd10);
        run_test(-16'sd10);
        run_test(16'sd200);
        run_test(-16'sd200);
        run_test(16'sd999);
        run_test(-16'sd999);
        $display("arctan tests done"); $finish;
    end

    task run_test(input signed [15:0] in_a);
    begin
        a = in_a; start = 1; #3.34; start = 0;
        wait(done); #5;
        $display("arctan(%d) = %d (0x%h)", in_a, result, result);
    end
    endtask
endmodule