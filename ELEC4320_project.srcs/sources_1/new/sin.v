//`define INPUTOUTBIT 32

// 要求
// 输入：整数，-999至999，角度制，需要能计算所有角度
// 输出统一用IEEE 754浮点数表示
// 误差要5%以内
// module里的注释用英文
// 不可以用IP和LUT
// CORDIC算法实现
// 内部定点格式位Q1.15 


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

 