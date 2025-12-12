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
    wire [`INPUTOUTBIT-1:0] result;
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
        .result(result),
        .cal_done(cal_done)
    );
    
    // Clock generation (300MHz = 3.33ns period)
    initial begin
        clk = 0;
        forever #1.67 clk = ~clk;
    end
    
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
        #100;
        
        // Test 1: Addition (5 + 3 = 8)
        $display("Test 1: Addition 5 + 3");
        sw = `OP_ADD;
        #100;
        
        // Input first operand (5)
        simulate_input(5);
        
        // Input second operand (3)
        simulate_input(3);
        
        // Wait for calculation to complete
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 8)", result);
        
        // Test 2: Subtraction (10 - 4 = 6)
        $display("\nTest 2: Subtraction 10 - 4");
        sw = `OP_SUB;
        #100;
        
        // Input first operand (10)
        simulate_input(10);
        
        // Input second operand (4)
        simulate_input(4);
        
        // Wait for calculation to complete
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 6)", result);
        
        // Test 3: Addition (100 + 200 = 300)
        $display("\nTest 3: Addition 100 + 200");
        sw = `OP_ADD;
        #100;
        
        simulate_input(100);
        simulate_input(200);
        
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 300)", result);
        
        // Test 4: Subtraction (50 - 30 = 20)
        $display("\nTest 4: Subtraction 50 - 30");
        sw = `OP_SUB;
        #100;
        
        simulate_input(50);
        simulate_input(30);
        
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 20)", result);
        
        // Test 5: Mutilpcation (2*3=6)
        $display("\nTest 5: Mutilpcation 2 * 3");
        sw = `OP_MUL;
        #100;
        
        simulate_input(2);
        simulate_input(3);
        
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 0x40C00000)", result);  
        
        // Test 6: Mutilpcation (-999*0=0)
        $display("\nTest 6: Mutilpcation -999 * 0");
        sw = `OP_MUL;
        #100;
        
        simulate_input(-999);
        simulate_input(0);
        
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 0x0)", result);  
        
        // Test 7: Mutilpcation (-321*-123=39483)
        $display("\nTest 7: Mutilpcation -321 * -123");
        sw = `OP_MUL;
        #100;
        
        simulate_input(-321);
        simulate_input(-123);
        
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 0x471a3b00)", result);          
        
        // Test 7: Mutilpcation (-1*1=-1)
        $display("\nTest 7: Mutilpcation -1 * 1");
        sw = `OP_MUL;
        #100;
        
        simulate_input(-1);
        simulate_input(1);
        
        wait(cal_done);
        #100;
        $display("Result: %d (Expected: 0xBF800000)", result);     
              
        $display("\nAll tests completed!");
        #1000;
        $finish;
    end
    
    // Task to simulate button input
    task simulate_input;
        input [`INPUTOUTBIT-1:0] value;
        integer i;
        reg [3:0] digit;
        begin
            // Simulate entering digits via buttons
            // This is a simplified version - in reality you'd need to 
            // simulate the actual button presses for each digit
            
            // For simulation, we can directly trigger the input_done signal
            // by simulating button presses
            
            // Wait for input controller to be ready
            #1000;
            
            // Press middle button to confirm input
            btn_mid = 1;
            #10000;  // Hold button for debounce time (10us)
            btn_mid = 0;
            #10000;  // Wait for input to be processed
        end
    endtask

    
    // Monitor signals
    initial begin
        $monitor("Time=%0t rst=%b sw=%b state=%b a_val=%d b_val=%d result=%d cal_done=%b", 
                 $time, rst, sw, uut.state, uut.a_val, uut.b_val, result, cal_done);
    end
    
    // Timeout watchdog
    initial begin
        #100000000;  // 100ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
