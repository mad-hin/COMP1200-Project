//`define INPUTOUTBIT 32

// 要求
// 输入：整数，-999至999，角度制，需要能计算所有角度
// 输出统一用IEEE 754浮点数表示
// 误差要5%以内
// module里的注释用英文
// 不可以用IP和LUT
// CORDIC算法实现，需要11次迭代
// 内部定点格式位Q1.15 
// 代码语言：Verilog 2001

`timescale 1ns / 1ps
`include "define.vh"

module sin(
    // Clock and reset
    input wire clk,
    input wire rst,
    
    // Start signal - triggers calculation when high
    input wire start,
    
    // Input angle in degrees (integer from -999 to 999)
    input wire signed [`INPUTOUTBIT-1:0] a,
    
    // Result output in IEEE 754 single-precision floating point format
    output reg [`INPUTOUTBIT-1:0] result,
    
    // Error flag: 1 = error occurred, 0 = no error
    output reg error,
    
    // Done flag: 1 = calculation complete, 0 = still processing
    output reg done
);
    
    // Internal parameters
    parameter integer ITERATIONS = 11;
    parameter integer Q15_SCALE = 32768;  // 2^15 for Q1.15 format
    parameter integer PI_Q15 = 32768;     // π in Q1.15 (π=3.14159... but we use 2π=65536)
    
    // Angle table for 11 iterations in Q1.15 format
    localparam signed [15:0] angle_table [0:10] = '{
        16'h2000,  // 45.0° = 8192 = π/4
        16'h12E4,  // 26.565° ≈ 4836
        16'h09FB,  // 14.036° ≈ 2555
        16'h0511,  // 7.125° ≈ 1297
        16'h028B,  // 3.576° ≈ 651
        16'h0146,  // 1.790° ≈ 326
        16'h00A3,  // 0.895° ≈ 163
        16'h0051,  // 0.448° ≈ 81
        16'h0029,  // 0.224° ≈ 41
        16'h0014,  // 0.112° ≈ 20
        16'h000A   // 0.056° ≈ 10
    };
    
    // CORDIC gain constant K = 0.6072529350088814 in Q1.15
    localparam signed [15:0] K_Q15 = 16'h26DD;  // 0.60725 * 32768 ≈ 19893
    
    // State machine
    reg [3:0] state;
    reg [3:0] iteration;
    
    // CORDIC registers (Q1.15 format)
    reg signed [15:0] x, y, z;
    reg signed [15:0] x_next, y_next, z_next;
    
    // Pre-processing: convert degrees to Q1.15 radians
    // 360° = 2π = 65536 in Q1.15, so 1° = 65536/360 = 182.044...
    // We'll use 182 (0xB6) for conversion
    wire signed [31:0] angle_deg_q15;
    assign angle_deg_q15 = a * 182;  // Convert to Q1.15 radians
    
    // Main state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
            done <= 0;
            error <= 0;
            x <= 0;
            y <= 0;
            z <= 0;
            iteration <= 0;
        end else begin
            case (state)
                0: begin  // IDLE
                    done <= 0;
                    if (start) begin
                        // Pre-processing: bring angle to [-π/2, π/2]
                        // Convert input angle to Q1.15 and normalize
                        reg signed [31:0] norm_angle;
                        norm_angle = angle_deg_q15;
                        
                        // Handle large angles: bring to [-π, π] range
                        while (norm_angle > 32768) norm_angle = norm_angle - 65536;
                        while (norm_angle < -32768) norm_angle = norm_angle + 65536;
                        
                        // Further reduce to [-π/2, π/2] using trigonometric identities
                        if (norm_angle > 16384) begin       // > π/2
                            z <= norm_angle - 32768;        // π radians
                            x <= -K_Q15;                    // cos(π - θ) = -cos(θ)
                        end else if (norm_angle < -16384) begin // < -π/2
                            z <= norm_angle + 32768;        // -π radians
                            x <= -K_Q15;
                        end else begin
                            z <= norm_angle;
                            x <= K_Q15;                     // Initial x = K
                        end
                        
                        y <= 0;                            // Initial y = 0
                        state <= 1;
                        iteration <= 0;
                        error <= 0;
                    end
                end
                
                1: begin  // ITERATION
                    // CORDIC iteration
                    if (z[15]) begin  // z < 0
                        x_next = x + (y >>> iteration);
                        y_next = y - (x >>> iteration);
                        z_next = z + angle_table[iteration];
                    end else begin    // z >= 0
                        x_next = x - (y >>> iteration);
                        y_next = y + (x >>> iteration);
                        z_next = z - angle_table[iteration];
                    end
                    
                    // Update registers
                    x <= x_next;
                    y <= y_next;
                    z <= z_next;
                    
                    // Check if done
                    if (iteration == ITERATIONS-1) begin
                        state <= 2;
                    end else begin
                        iteration <= iteration + 1;
                    end
                end
                
                2: begin  // CONVERT TO IEEE754
                    // y now contains sin(angle) in Q1.15 format
                    // Convert to IEEE754 single precision
                    
                    // Handle sign
                    reg sign;
                    reg [31:0] abs_y;
                    reg [7:0] exponent;
                    reg [22:0] mantissa;
                    reg [4:0] leading_one;
                    
                    sign = y[15];
                    abs_y = y[15] ? -y : y;  // Absolute value
                    
                    if (abs_y == 0) begin
                        // Zero case
                        result <= 32'h00000000;
                    end else begin
                        // Find leading one (most significant 1 bit)
                        leading_one = 15;
                        if (abs_y[14]) leading_one = 14;
                        else if (abs_y[13]) leading_one = 13;
                        else if (abs_y[12]) leading_one = 12;
                        else if (abs_y[11]) leading_one = 11;
                        else if (abs_y[10]) leading_one = 10;
                        else if (abs_y[9]) leading_one = 9;
                        else if (abs_y[8]) leading_one = 8;
                        else if (abs_y[7]) leading_one = 7;
                        else if (abs_y[6]) leading_one = 6;
                        else if (abs_y[5]) leading_one = 5;
                        else if (abs_y[4]) leading_one = 4;
                        else if (abs_y[3]) leading_one = 3;
                        else if (abs_y[2]) leading_one = 2;
                        else if (abs_y[1]) leading_one = 1;
                        else leading_one = 0;
                        
                        // Calculate exponent (biased by 127)
                        // In Q1.15, value range is [-1, 1), so exponent is 126 (0x7E)
                        exponent = 8'd126;
                        
                        // Calculate mantissa (23 bits)
                        // Shift left to normalize (implicit 1.xxx format)
                        if (leading_one >= 14) begin
                            // Number is in range [0.5, 1)
                            mantissa = (abs_y << (23 - (leading_one - 14))) & 23'h7FFFFF;
                        end else begin
                            // Number is in range [0, 0.5), need to adjust exponent
                            exponent = exponent - (14 - leading_one);
                            mantissa = (abs_y << (23 - leading_one)) & 23'h7FFFFF;
                        end
                        
                        // Pack IEEE754 format: sign(1) + exponent(8) + mantissa(23)
                        result <= {sign, exponent, mantissa};
                    end
                    
                    done <= 1;
                    state <= 0;
                end
            endcase
        end
    end
    
endmodule