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
    
    // Timing parameters
    localparam DEBOUNCE_TIME = 2100000;  // 2.1ms - just over debounce threshold
    localparam BUTTON_GAP = 3000000;      // 3ms gap - ensure debouncer fully resets
    localparam RESET_TIME = 1000000;      // 1ms reset pulse
    localparam SETTLE_TIME = 10000000;    // 10ms settle after reset
    
    // Task to perform system reset
    task system_reset;
        begin
            $display("  [RESET] Resetting system...");
            rst = 1;
            btn_left = 0;
            btn_right = 0;
            btn_up = 0;
            btn_down = 0;
            btn_mid = 0;
            #RESET_TIME;
            rst = 0;
            #SETTLE_TIME;
            $display("  [RESET] System ready.");
        end
    endtask
    
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
        
        // Initial reset
        #100;
        rst = 0;
        #SETTLE_TIME;
        
        $display("[DEBUG] Initial alu_result=0x%04h, alu_error=%b, cal_done=%b", 
            alu_result, alu_error, cal_done);

        // =====================================================
        // Test 1: Addition (5 + 3 = 8)
        // =====================================================
       $display("\n=== Test 1: Addition 5 + 3 ===");
       system_reset();
       sw = `OP_ADD;
       #1000000;
        
       simulate_input(5);
       #5000000;
       simulate_input(3);
        
       wait(cal_done);
       #100000;
       $display("Result: 0x%04h (Expected: 0x4100 = 8.0)", alu_result);
        
        // =====================================================
        // Test 2: Addition (-100 + 200 = 100)
        // =====================================================
       $display("\n=== Test 2: Addition -100 + 200 ===");
       system_reset();
       sw = `OP_ADD;
       #1000000;
        
       simulate_input(-100);
       #5000000;
       simulate_input(200);
        
       wait(cal_done);
       #100000;
       $display("Result: 0x%04h (Expected: 0x42C8 = 100.0)", alu_result);
        
        // =====================================================
        // Test 3: Addition (-50 + -30 = -80)
//        // =====================================================
       $display("\n=== Test 3: Addition -50 + -30 ===");
       system_reset();
       sw = `OP_ADD;
       #1000000;
        
       simulate_input(-50);
       #5000000;
       simulate_input(-30);
        
       wait(cal_done);
       #100000;
       $display("Result: 0x%04h (Expected: 0xC2A0 = -80.0)", alu_result);
        
        // =====================================================
        // Test 4: Subtraction (10 - 4 = 6)
        // =====================================================
        $display("\n=== Test 4: Subtraction 10 - 4 ===");
        system_reset();
        sw = `OP_SUB;
        #1000000;
        
        simulate_input(10);
        #5000000;
        simulate_input(4);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x40C0 = 6.0)", alu_result);
        
        // =====================================================
        // Test 5: Subtraction (50 - 30 = 20)
        // =====================================================
        $display("\n=== Test 5: Subtraction 50 - 30 ===");
        system_reset();
        sw = `OP_SUB;
        #1000000;
        
        simulate_input(50);
        #5000000;
        simulate_input(30);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x41A0 = 20.0)", alu_result);

        // =====================================================
        // Test 6: Subtraction (-23 - 5 = -28)
        // =====================================================
        $display("\n=== Test 6: Subtraction -23 - 5 ===");
        system_reset();
        sw = `OP_SUB;
        #1000000;
        
        simulate_input(-23);
        #5000000;
        simulate_input(5);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0xC1E0 = -28.0)", alu_result);
    
        
        // =====================================================
        // Test 7: Multiplication (2 * 3 = 6)
        // =====================================================
        $display("\n=== Test 7: Multiplication 2 * 3 ===");
        system_reset();
        sw = `OP_MUL;
        #1000000;
        
        simulate_input(2);
        #5000000;
        simulate_input(3);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x40C0 = 6.0)", alu_result);
        
        // =====================================================
        // Test 8: Multiplication (-999 * 0 = 0)
        // =====================================================
        $display("\n=== Test 8: Multiplication -999 * 0 ===");
        system_reset();
        sw = `OP_MUL;
        #1000000;
        
        simulate_input(-999);
        #5000000;
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0)", alu_result);
        
        // =====================================================
        // Test 9: Multiplication (-321 * -123 = 39483)
        // =====================================================
        $display("\n=== Test 9: Multiplication -321 * -123 ===");
        system_reset();
        sw = `OP_MUL;
        #1000000;
        
        simulate_input(-321);
        #5000000;
        simulate_input(-123);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x471A = 39483.0)", alu_result);
        
        // =====================================================
        // Test 10: Division (5 / 2 = 2.5)
        // =====================================================
        $display("\n=== Test 10: Division 5 / 2 ===");
        system_reset();
        sw = `OP_DIV;
        #1000000;
        
        simulate_input(5);
        #5000000;
        simulate_input(2);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x4020 = 2.5)", alu_result);
        
        // =====================================================
        // Test 11: Division (-999 / 3 = -333)
        // =====================================================
        $display("\n=== Test 11: Division -999 / 3 ===");
        system_reset();
        sw = `OP_DIV;
        #1000000;
        
        simulate_input(-999);
        #5000000;
        simulate_input(3);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0xC3A6 = -333.0)", alu_result);
        
        // =====================================================
        // Test 12: Division (100 / -3 = -33.333...)
        // =====================================================
        $display("\n=== Test 12: Division 100 / -3 ===");
        system_reset();
        sw = `OP_DIV;
        #1000000;
        
        simulate_input(100);
        #5000000;
        simulate_input(-3);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0xC205 = -33.33)", alu_result);
        
        // =====================================================
        // Test 13: Division by Zero (999 / 0 = ERROR)
        // =====================================================
        $display("\n=== Test 13: Division 999 / 0 (ERROR) ===");
        system_reset();
        sw = `OP_DIV;
        #1000000;
        
        simulate_input(999);
        #5000000;
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h, Error: %b (Expected: ERROR)", alu_result, alu_error);
        
        // =====================================================
        // Test 14: Logarithm (log10(100) = 2)
        // =====================================================
        $display("\n=== Test 14: Logarithm log10(100) ===");
        system_reset();
        sw = `OP_LOG;
        #1000000;
        
        simulate_input(10);
        #5000000;
        simulate_input(100);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x4000 = 2.0)", alu_result);
        
        // =====================================================
        // Test 15: Logarithm (log2(8) = 3)
        // =====================================================
        $display("\n=== Test 15: Logarithm log2(8) ===");
        system_reset();
        sw = `OP_LOG;
        #1000000;
        
        simulate_input(2);
        #5000000;
        simulate_input(8);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x4040 = 3.0)", alu_result);
        
        // =====================================================
        // Test 16: Power (2^3 = 8)
        // =====================================================
         $display("\n=== Test 16: Power 2^3 ===");
         system_reset();
         sw = `OP_POW;
         #1000000;
        
         simulate_input(2);
         #5000000;
         simulate_input(3);
        
         wait(cal_done);
         #100000;
         $display("Result: 0x%04h (Expected: 0x4100 = 8.0)", alu_result);
        
        // =====================================================
        // Test 17: Power (99^0 = 1)
        // =====================================================
        $display("\n=== Test 17: Power 99^0 ===");
        system_reset();
        sw = `OP_POW;
        #1000000;
        
        simulate_input(99);
        #5000000;
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 18: Square Root (sqrt(4) = 2)
        // =====================================================
        $display("\n=== Test 18: Square Root sqrt(4) ===");
        system_reset();
        sw = `OP_SQRT;
        #1000000;
        
        simulate_input(4);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x4000 = 2.0)", alu_result);
        
        // =====================================================
        // Test 19: Square Root (sqrt(2) = 1.414...)
        // =====================================================
        $display("\n=== Test 19: Square Root sqrt(2) ===");
        system_reset();
        sw = `OP_SQRT;
        #1000000;
        
        simulate_input(2);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3FB5 = 1.414)", alu_result);
        
        // =====================================================
        // Test 20: Exponential (e^2 = 7.389...)
        // =====================================================
        $display("\n=== Test 20: Exponential e^2 ===");
        system_reset();
        sw = `OP_EXP;
        #1000000;
        
        simulate_input(2);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x40EC = 7.389)", alu_result);
        
        // =====================================================
        // Test 21: Exponential (e^0 = 1)
        // =====================================================
        $display("\n=== Test 21: Exponential e^0 ===");
        system_reset();
        sw = `OP_EXP;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 22: Sin (sin(0) = 0)
        // =====================================================
        $display("\n=== Test 22: Sin sin(0) ===");
        system_reset();
        sw = `OP_SIN;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0)", alu_result);
        
        // =====================================================
        // Test 23: Sin (sin(90) = 1) - input in degrees
        // =====================================================
        $display("\n=== Test 23: Sin sin(90) ===");
        system_reset();
        sw = `OP_SIN;
        #1000000;
        
        simulate_input(90);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 24: Sin (sin(30) = 0.5) - input in degrees
        // =====================================================
        $display("\n=== Test 24: Sin sin(30) ===");
        system_reset();
        sw = `OP_SIN;
        #1000000;
        
        simulate_input(30);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F00 = 0.5)", alu_result);
        
        // =====================================================
        // Test 25: Cos (cos(0) = 1)
        // =====================================================
        $display("\n=== Test 25: Cos cos(0) ===");
        system_reset();
        sw = `OP_COS;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 26: Cos (cos(90) = 0) - input in degrees
        // =====================================================
        $display("\n=== Test 26: Cos cos(90) ===");
        system_reset();
        sw = `OP_COS;
        #1000000;
        
        simulate_input(90);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0)", alu_result);
        
        // =====================================================
        // Test 27: Cos (cos(60) = 0.5) - input in degrees
        // =====================================================
        $display("\n=== Test 27: Cos cos(60) ===");
        system_reset();
        sw = `OP_COS;
        #1000000;
        
        simulate_input(60);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F00 = 0.5)", alu_result);
        
        // =====================================================
        // Test 28: Tan (tan(0) = 0)
        // =====================================================
        $display("\n=== Test 28: Tan tan(0) ===");
        system_reset();
        sw = `OP_TAN;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0)", alu_result);
        
        // =====================================================
        // Test 29: Tan (tan(45) = 1) - input in degrees
        // =====================================================
        $display("\n=== Test 29: Tan tan(45) ===");
        system_reset();
        sw = `OP_TAN;
        #1000000;
        
        simulate_input(45);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 30: Arcsin (asin(0) = 0 degrees)
        // =====================================================
        $display("\n=== Test 30: Arcsin asin(0) ===");
        system_reset();
        sw = `OP_ASIN;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0 degrees)", alu_result);
        
        // =====================================================
        // Test 31: Arcsin (asin(1) = 90 degrees)
        // Note: Input 1 represents sin value, output in degrees
        // =====================================================
        $display("\n=== Test 31: Arcsin asin(1) ===");
        system_reset();
        sw = `OP_ASIN;
        #1000000;
        
        simulate_input(1);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x42B4 = 90.0 degrees)", alu_result);
        
        // =====================================================
        // Test 32: Arccos (acos(1) = 0 degrees)
        // =====================================================
        $display("\n=== Test 32: Arccos acos(1) ===");
        system_reset();
        sw = `OP_ACOS;
        #1000000;
        
        simulate_input(1);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0 degrees)", alu_result);
        
        // =====================================================
        // Test 33: Arccos (acos(0) = 90 degrees)
        // =====================================================
        $display("\n=== Test 33: Arccos acos(0) ===");
        system_reset();
        sw = `OP_ACOS;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x42B4 = 90.0 degrees)", alu_result);
        
        // =====================================================
        // Test 34: Arctan (atan(0) = 0 degrees)
        // =====================================================
        $display("\n=== Test 34: Arctan atan(0) ===");
        system_reset();
        sw = `OP_ATAN;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x0000 = 0.0 degrees)", alu_result);
        
        // =====================================================
        // Test 35: Arctan (atan(1) = 45 degrees)
        // =====================================================
        $display("\n=== Test 35: Arctan atan(1) ===");
        system_reset();
        sw = `OP_ATAN;
        #1000000;
        
        simulate_input(1);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x4234 = 45.0 degrees)", alu_result);
        
        // =====================================================
        // Test 36: Factorial (0! = 1)
        // =====================================================
        $display("\n=== Test 36: Factorial 0! ===");
        system_reset();
        sw = `OP_FAC;
        #1000000;
        
        simulate_input(0);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 37: Factorial (1! = 1)
        // =====================================================
        $display("\n=== Test 37: Factorial 1! ===");
        system_reset();
        sw = `OP_FAC;
        #1000000;
        
        simulate_input(1);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x3F80 = 1.0)", alu_result);
        
        // =====================================================
        // Test 38: Factorial (5! = 120)
        // =====================================================
        $display("\n=== Test 38: Factorial 5! ===");
        system_reset();
        sw = `OP_FAC;
        #1000000;
        
        simulate_input(5);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x42F0 = 120.0)", alu_result);
        
        // =====================================================
        // Test 39: Factorial (7! = 5040)
        // =====================================================
        $display("\n=== Test 39: Factorial 7! ===");
        system_reset();
        sw = `OP_FAC;
        #1000000;
        
        simulate_input(7);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x459D = 5040.0)", alu_result);
        
        // =====================================================
        // Test 40: Factorial (10! = 3628800)
        // =====================================================
        $display("\n=== Test 40: Factorial 10! ===");
        system_reset();
        sw = `OP_FAC;
        #1000000;
        
        simulate_input(10);
        
        wait(cal_done);
        #100000;
        $display("Result: 0x%04h (Expected: 0x4A5D = 3628800.0)", alu_result);

        $display("\n=== All tests completed! ===");
        #1000000;
        $finish;
    end

    // Task to simulate button input (supports -999 to 999)
    task simulate_input;
        input signed [15:0] value;
        reg is_negative;
        reg [9:0] abs_value;
        reg [3:0] units, tens, hundreds;
        begin
            // Determine sign and absolute value
            if (value < 0) begin
                is_negative = 1;
                abs_value = -value;
            end else begin
                is_negative = 0;
                abs_value = value;
            end
            
            // Extract individual digits from absolute value
            units = abs_value % 10;
            tens = (abs_value / 10) % 10;
            hundreds = (abs_value / 100) % 10;
            
            if (is_negative)
                $display("Value: -%0d (sign=-, hundreds=%0d, tens=%0d, units=%0d)", abs_value, hundreds, tens, units);
            else
                $display("Value: %0d (sign=+, hundreds=%0d, tens=%0d, units=%0d)", abs_value, hundreds, tens, units);
            
            // Input starts at units position (current_digit = 0)
            // Set units digit
            $display("Setting units digit: %0d", units);
            repeat(units) press_button_up();
            
            // Move to tens digit and set it
            if (abs_value >= 10 || is_negative) begin
                press_button_left();
                $display("Setting tens digit: %0d", tens);
                repeat(tens) press_button_up();
            end
            
            // Move to hundreds digit and set it
            if (abs_value >= 100 || is_negative) begin
                press_button_left();
                $display("Setting hundreds digit: %0d", hundreds);
                repeat(hundreds) press_button_up();
            end
            
            // Set sign bit if negative
            if (is_negative) begin
                press_button_left();  // Move to sign position
                $display("Setting sign: negative");
                press_button_up();  // Toggle sign bit
            end
            
            // Press middle button to confirm input
            $display("Confirming input...");
            press_button_mid();
            
            // Wait for input processing
            #5000000;
            $display("Input complete");
        end
    endtask
    
    // Task to press UP button with proper debounce timing
    task press_button_up;
        begin
            btn_up = 1;
            #DEBOUNCE_TIME;
            btn_up = 0;
            #BUTTON_GAP;
        end
    endtask
    
    // Task to press DOWN button with proper debounce timing
    task press_button_down;
        begin
            btn_down = 1;
            #DEBOUNCE_TIME;
            btn_down = 0;
            #BUTTON_GAP;
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
            #(DEBOUNCE_TIME+500000);
            btn_mid = 0;
            #BUTTON_GAP;
        end
    endtask
    
    // Debug monitor - watch key signals
    initial begin
        $monitor("Time=%0t state=%d a_val=%d b_val=%d input_val=%d input_done=%b cal_done=%b result=0x%04h", 
                 $time, uut.state, uut.a_val, uut.b_val, uut.input_val, uut.io_ctrl.input_done, cal_done, alu_result);
    end
    
    // Timeout watchdog
    initial begin
        #2000000000;  // 2s timeout (increased for multiple tests)
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule