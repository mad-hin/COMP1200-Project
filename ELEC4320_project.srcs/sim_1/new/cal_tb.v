`timescale 1ns / 1ps

`include "define.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.12.2025 18:39:47
// Design Name: 
// Module Name: cal_tb
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
module cal_tb();

    // Clock and reset
    reg clk;
    reg rst;
    
    // Inputs
    reg [3:0] sw;
    reg btn_left, btn_right, btn_up, btn_down, btn_mid;
    
    // Outputs
    wire [6:0] seg;
    wire [3:0] an;
    wire [`INPUTOUTBIT-1:0] alu_result;
    wire alu_error;
    wire cal_done;
    
    // Instantiate the ALU
    alu uut (
        .clk(clk),
        .rst(rst),
        .sw(sw),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .btn_up(btn_up),
        .btn_down(btn_down),
        .btn_mid(btn_mid),
        .seg(seg),
        .an(an),
        .result(alu_result),
        .error(alu_error),
        .cal_done(cal_done)
    );
    
    // Clock generation (300MHz = 3.33ns period)
    initial begin
        clk = 0;
        forever #1.67 clk = ~clk;
    end
    
    // Debounce time calculation:
    // clk_slow = 300MHz / 3 = 100MHz (10ns period)
    // STABLE = 200000 cycles at 100MHz = 2ms = 2,000,000 ns
    // Need to hold button for > 2ms
    localparam DEBOUNCE_TIME = 2500000;  // 2.5ms in ns (with margin)
    localparam BUTTON_GAP = 500000;       // 0.5ms gap between button presses
    
    // Test stimulus
    initial begin
        // Initialize inputs
        rst = 1;
        sw = 0;
        btn_left = 0;
        btn_right = 0;
        btn_up = 0;
        btn_down = 0;
        btn_mid = 0;
        
        // Reset the system
        #100;
        rst = 0;
        #5000000;  // Wait 5ms for system to settle
        
        // Test 1: Addition (5 + 3 = 8)
        $display("\n=== Test 1: Addition 5 + 3 ===");
        sw = `OP_ADD;
        #1000000;  // Wait 1ms
        
        // Input first operand (5)
        simulate_input(5);
        
        // Input second operand (3)
        simulate_input(3);
        
        // Wait for calculation to complete
        wait(cal_done);
        #100000;
        $display("Result: %d (Expected: 8)", alu_result);
        
        #5000000;  // Wait 5ms between tests
        
        // Test 2: Addition (100 + 200 = 300)
        $display("\n=== Test 2: Addition 100 + 200 ===");
        sw = `OP_ADD;
        #1000000;
        
        simulate_input(100);
        simulate_input(200);
        
        wait(cal_done);
        #100000;
        $display("Result: %d (Expected: 300)", alu_result);
                                                                         
        $display("\n=== All tests completed! ===");
        #1000000;
        $finish;
    end
    
    // Task to simulate button input
    task simulate_input;
        input [`INPUTOUTBIT-1:0] value;
        integer i, digit_count, temp_value;
        reg [3:0] digits [2:0];  // Store up to 3 digits
        begin
            // Extract individual digits
            digits[0] = value % 10;           // units
            digits[1] = (value / 10) % 10;    // tens
            digits[2] = (value / 100) % 10;   // hundreds
            
            // Count significant digits
            if (value >= 100)
                digit_count = 3;
            else if (value >= 10)
                digit_count = 2;
            else
                digit_count = 1;
            
            $display("  Inputting value: %d", value);
            
            // Input starts at units position (current_digit = 0)
            // First, set units digit
            $display("    Setting units digit: %d", digits[0]);
            input_digit(digits[0]);
            
            // If we have tens digit, move left and set it
            if (digit_count >= 2) begin
                // Move to tens position
                press_button_left();
                $display("    Setting tens digit: %d", digits[1]);
                input_digit(digits[1]);
            end
            
            // If we have hundreds digit, move left and set it
            if (digit_count >= 3) begin
                // Move to hundreds position
                press_button_left();
                $display("    Setting hundreds digit: %d", digits[2]);
                input_digit(digits[2]);
            end
            
            // Press middle button to confirm input
            $display("    Confirming input...");
            press_button_mid();
            
            // Wait for input_done to propagate
            #5000000;  // Wait 5ms for synchronization
            $display("  Input complete!");
        end
    endtask

    // Helper task to input a single digit by pressing up button
    task input_digit;
        input [3:0] digit;
        integer j;
        begin
            for (j = 0; j < digit; j = j + 1) begin
                press_button_up();
            end
        end
    endtask
    
    // Task to press UP button with proper debounce timing
    task press_button_up;
        begin
            btn_up = 1;
            #DEBOUNCE_TIME;  // Hold for debounce time
            btn_up = 0;
            #BUTTON_GAP;     // Gap between presses
        end
    endtask
    
    // Task to press LEFT button with proper debounce timing
    task press_button_left;
        begin
            btn_left = 1;
            #DEBOUNCE_TIME;
            btn_left = 0;
            #BUTTON_GAP;
        end
    endtask
    
    // Task to press RIGHT button with proper debounce timing
    task press_button_right;
        begin
            btn_right = 1;
            #DEBOUNCE_TIME;
            btn_right = 0;
            #BUTTON_GAP;
        end
    endtask
    
    // Task to press MID button with proper debounce timing
    task press_button_mid;
        begin
            btn_mid = 1;
            #DEBOUNCE_TIME;
            btn_mid = 0;
            #BUTTON_GAP;
        end
    endtask
    
    // Monitor key signals
    initial begin
        $monitor("Time=%0t rst=%b sw=%b state=%d input_done=%b a_val=%d b_val=%d result=%d cal_done=%b", 
                 $time, rst, sw, uut.state, uut.io_ctrl.input_done, uut.a_val, uut.b_val, alu_result, cal_done);
    end
    
    // Timeout watchdog
    initial begin
        #500000000;  // 500ms timeout (increased due to longer debounce times)
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule