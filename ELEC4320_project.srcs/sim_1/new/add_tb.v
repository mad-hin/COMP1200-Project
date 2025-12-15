`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.12.2025 15:17:26
// Design Name: 
// Module Name: add_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module add_tb();
    // Clock and reset
    reg clk;
    reg rst;

    wire [`INPUTOUTBIT-1:0] result;
    wire done;
    wire error;
    reg signed [`INPUTOUTBIT-1:0] a;
    reg signed [`INPUTOUTBIT-1:0] b;
    reg start;
    reg add_sub_flag;

    add uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
        .b(b),
        .add_sub_flag(add_sub_flag),
        .result(result),
        .error(error),
        .done(done)
    );
    
    // Clock generation (300MHz = 3.33ns period)
    initial begin
        clk = 0;
        forever #1.67 clk = ~clk;
    end

    // Test sequence
    initial begin
        // Initialize inputs
        rst = 1;
        a = 0;
        b = 0;
        add_sub_flag = 0;
        start = 0;

        // Wait for reset
        #100;
        rst = 0;
        #20;

        // Test Case 1: 10 + 20 = 30
        run_test(16'd10, 16'd20, 0);

        // Test Case 2: -10 + (-20) = -30
        run_test(-16'sd10, -16'sd20, 0);

        // Test Case 3: 50 + (-20) = 30
        run_test(16'd50, -16'sd20, 0);

        // Test Case 4: -50 + 20 = -30
        run_test(-16'sd50, 16'd20, 0);

        // Test Case 5: 999 + 999 = 1998
        run_test(16'd999, 16'd999, 0);

        // Test Case 6: -999 + (-999) = -1998
        run_test(-16'sd999, -16'sd999, 0);

        // Test Case 7: 999 + (-999) = 0
        run_test(16'd999, -16'sd999, 0);

        // Test Case 8: 0 + 0 = 0
        run_test(16'd0, 16'd0, 0);

        // Test Case 9: Subtraction 50 - 20 = 30
        run_test(16'd50, 16'd20, 1);

        // Test Case 10: Subtraction 20 - 50 = -30
        run_test(16'd20, 16'd50, 1);

        $display("All tests completed.");
        $finish;
    end

    // Task to run a single test case
    // Note: Inputs are integers, converted to BF16 inside the task if the DUT expects BF16,
    // OR if the DUT expects integers directly (based on your prompt saying "range -999 to 999 all integer"),
    // we pass them directly. Assuming DUT handles the format or expects these bits.
    task run_test;
        input signed [15:0] in_a;
        input signed [15:0] in_b;
        input sub_flag;
        begin
            // 1. Setup inputs
            a = in_a;
            b = in_b;
            add_sub_flag = sub_flag;
            
            // 2. Pulse start
            start = 1;
            #3.34; // Wait one clock cycle (approx)
            start = 0;

            // 3. Wait for done
            wait(done);
            #5; // Hold for a bit to see result

            // 4. Display result
            if (sub_flag)
                $display("Test: %d - %d = %d (Hex: %h)", in_a, in_b, result, result);
            else
                $display("Test: %d + %d = %d (Hex: %h)", in_a, in_b, result, result);
            
            // 5. Wait before next test
        end
    endtask
endmodule
