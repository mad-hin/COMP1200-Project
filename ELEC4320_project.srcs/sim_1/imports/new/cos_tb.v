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


module cos_tb();
    // Clock and reset
    reg clk;
    reg rst;

    wire [`INPUTOUTBIT-1:0] result;
    wire done;
    wire error;
    reg signed [`INPUTOUTBIT-1:0] a;
    reg start;
    reg add_sub_flag;

    cos uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
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
        add_sub_flag = 0;
        start = 0;

        // Wait for reset
        #100;
        rst = 0;
        #20;

        // Test Case 1: cos(10)
        run_test(16'd10);

        // Test Case 2: cos(-10)
        run_test(-16'sd10);

        // Test Case 3: cos(50)
        run_test(16'd50);

        // Test Case 4: cos(-50)
        run_test(-16'sd50);

        // Test Case 5: cos(999)
        run_test(16'd999);

        // Test Case 6: cos(-999)
        run_test(-16'sd999);

        // Test Case 8: cos(0)
        run_test(16'd0);

        // Test Case 10: cos(20)
        run_test(16'd20);

        $display("All tests completed.");
        $finish;
    end

    // Task to run a single test case
    // Note: Inputs are integers, converted to BF16 inside the task if the DUT expects BF16,
    // OR if the DUT expects integers directly (based on your prompt saying "range -999 to 999 all integer"),
    // we pass them directly. Assuming DUT handles the format or expects these bits.
    task run_test;
        input signed [15:0] in_a;
        begin
            // 1. Setup inputs
            a = in_a;
            
            // 2. Pulse start
            start = 1;
            #3.34; // Wait one clock cycle (approx)
            start = 0;

            // 3. Wait for done
            wait(done);
            #5; // Hold for a bit to see result

            // 4. Display result
            $display("Test: cos(%d) = %d (Hex: %h)", in_a, result, result);
            
            // 5. Wait before next test
        end
    endtask
endmodule
