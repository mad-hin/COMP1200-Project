`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/13 02:13:38
// Design Name: 
// Module Name: exp
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
module exp(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a, // Integer Input
    output reg  signed [`INPUTOUTBIT-1:0] result, // BF16
    output reg  error,
    output reg  done
);

    // ==========================================
    // Constants
    // ==========================================
    localparam signed [31:0] LN2_FIXED=32'h0000_B172; 
    localparam signed [31:0] RECIP_LN2=32'h0001_7154; 
    localparam signed [31:0] CORDIC_K=32'h0001_3521; 
    localparam ITERATIONS = 16;

    reg [3:0] state;
    localparam  S_IDLE=0, 
                S_REDUCE_1=1,
                S_REDUCE_2=2, 
                S_CALC=3, 
                S_CONVERT=4, 
                S_DONE=5;

    // CORDIC Vars
    reg signed [31:0] x, y, z;
    reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i;
    reg repeat_done;
    
    // Range Reduction Vars
    reg signed [63:0] temp_calc;
    reg signed [31:0] k_integer;
    reg signed [31:0] a_extended;

    // BF16 Conversion Vars
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [31:0] calc_exp;
    reg [6:0]  bf16_mant;

    // ATANH ROM (same values for CORDIC hyperbolic)
    reg signed [31:0] atanh_val;
    always @(*) begin
        case(i)
            1:  atanh_val=32'h0000_8C9F;
            2:  atanh_val=32'h0000_4162;
            3:  atanh_val=32'h0000_202B;
            4:  atanh_val=32'h0000_1005;
            5:  atanh_val=32'h0000_0800;
            6:  atanh_val=32'h0000_0400;
            7:  atanh_val=32'h0000_0200;
            8:  atanh_val=32'h0000_0100;
            9:  atanh_val=32'h0000_0080;
            10: atanh_val=32'h0000_0040;
            11: atanh_val=32'h0000_0020;
            12: atanh_val=32'h0000_0010;
            13: atanh_val=32'h0000_0008;
            14: atanh_val=32'h0000_0004;
            15: atanh_val=32'h0000_0002;
            16: atanh_val=32'h0000_0001;
            default: atanh_val=0;
        endcase
    end
    
    // CLZ Function
    function [5:0] clz;
        input [31:0] val;
        integer k;
        begin
            clz=0;
            begin: clz_loop 
                for(k=31; k>=0; k=k-1) begin
                    if(val[k]) disable clz_loop;
                    clz=clz+1;
                end
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=S_IDLE;
            result<=0;
            error<=0; 
            done<=0;
        end else begin
            case(state)
                S_IDLE: begin
                    done<=0; 
                    error<=0;
                    if(start) 
                        state<=S_REDUCE_1;
                end

                // Range Reduction: Compute k = floor(a / ln(2))
                S_REDUCE_1: begin
                    a_extended={{16{a[15]}}, a};
                    temp_calc=$signed(a_extended)*RECIP_LN2;
                    k_integer<=temp_calc>>>16; 
                    state<=S_REDUCE_2;
                end

                // Range Reduction Step 2: Compute r = a - k * ln(2)
                S_REDUCE_2: begin
                    z<=($signed(a_extended)<<16)-(k_integer*LN2_FIXED);
                    x<=CORDIC_K;
                    y<=CORDIC_K;
                    i<=1;
                    repeat_done<=0;
                    state<=S_CALC;
                end

                S_CALC: begin
                    if(z[31] == 0) begin 
                        x_next=x+(y>>>i);
                        y_next=y+(x>>>i); 
                        z_next=z-atanh_val; 
                    end
                    else begin 
                        x_next=x-(y>>>i);
                        y_next=y-(x>>>i); 
                        z_next=z+atanh_val; 
                    end
                    x<=x_next;
                    y<=y_next; 
                    z<=z_next;

                    if(i<=ITERATIONS) begin
                        if((i==4||i==13)&&!repeat_done) 
                            repeat_done<=1; 
                        else begin 
                            i<=i+1; 
                            repeat_done<=0; 
                        end
                    end else begin
                        state<=S_CONVERT;
                    end
                end

                S_CONVERT: begin
                    abs_final=(x + y);
                    abs_final=abs_final[31] ? -abs_final : abs_final;
                    
                    if(abs_final==0) begin
                        result<=16'b0;
                    end else begin
                        norm_shift=clz(abs_final);
                        calc_exp=141-norm_shift+k_integer;
                        
                        // Extract 7-bit mantissa for BF16
                        bf16_mant=(abs_final<<norm_shift)>>24;

                        // Overflow
                        if(calc_exp>=255) begin
                            error<=1;
                            result<=16'h7F80;  // BF16 +Inf

                        // Underflow -> 0
                        end else if (calc_exp<=0) begin
                            result<=16'b0;

                        end else begin
                            // Pack BF16: {sign=0, exp[7:0], mant[6:0]}
                            result<={1'b0, calc_exp[7:0], bf16_mant};
                        end
                    end
                    state<=S_DONE;
                end

                S_DONE: begin
                    done<=1; 
                    if(!start) 
                        state<=S_IDLE;
                end
            endcase
        end
    end
endmodule