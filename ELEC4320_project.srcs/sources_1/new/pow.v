`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 21:35:12
// Design Name: 
// Module Name: pow
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
module pow(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [31:0] a,
    input wire signed [31:0] b,
    output reg signed [31:0] result, // 32 bit IEEE754
    output reg error,
    output reg done
);

    // ==========================================
    // Constants
    // ==========================================
    localparam signed [31:0] LN2_FIXED    = 32'h0000_B172; 
    localparam signed [31:0] RECIP_LN2    = 32'h0001_7154; 
    localparam signed [31:0] CORDIC_K     = 32'h0001_3521; 
    localparam ITERATIONS = 16;

    // ==========================================
    // Pipelined FSM States
    // ==========================================
    reg [4:0] state; // Expanded to 5 bits for more states
    
    localparam S_IDLE           = 0;
    localparam S_VALIDATE       = 1;
    
    // Split Normalization (CLZ -> Shift)
    localparam S_PREP_LN_CLZ    = 2; 
    localparam S_PREP_LN_SHIFT  = 3;
    
    localparam S_CALC_LN        = 4;
    
    // Split Multiplication (Load -> Calc)
    localparam S_MULT_1         = 5; 
    localparam S_MULT_2         = 6; 
    
    // Split Range Reduction K (Load -> Calc)
    localparam S_REDUCE_K_1     = 7;
    localparam S_REDUCE_K_2     = 8;
    
    // Split Range Reduction R (Load -> Calc -> Sub)
    localparam S_REDUCE_R_1     = 9;
    localparam S_REDUCE_R_2     = 10;
    
    localparam S_CALC_EXP       = 11;
    
    // Split Output Conv (Abs -> CLZ -> Shift)
    localparam S_CONVERT_CLZ    = 12; 
    localparam S_CONVERT_SHIFT  = 13;
    localparam S_CONVERT_PACK   = 14; 
    
    localparam S_DONE           = 15;

    // ==========================================
    // Internal Signals
    // ==========================================
    reg signed [31:0] x, y, z;
    reg signed [31:0] x_next, y_next, z_next;
    reg [4:0] i;
    reg repeat_done;
    reg signed [31:0] abs_a;
    reg result_is_neg;
    reg signed [31:0] ln_a_val;
    
    // Pipelined Multiplier Registers
    // 32x32 mult produces 64 bits. 
    // We register inputs and outputs to break timing paths.
    reg signed [31:0] mult_op_a, mult_op_b;
    reg signed [63:0] mult_result; 
    
    reg signed [31:0] k_integer;
    reg signed [31:0] current_input;
    reg [5:0] shift_count;
    reg [31:0] abs_final;
    reg [5:0]  norm_shift;
    reg signed [31:0] e_ln2;
    reg [31:0] ieee_comb; 
    reg signed [31:0] calc_exp; 
    reg signed [63:0] temp_mult;
    reg signed [63:0] temp_kln2;
    // ATANH ROM (Combinational is fine if small, 
    // but ensuring 'i' is stable is key. 'i' comes from FF, so this is safe).
    reg signed [31:0] atanh_val;
    always @(*) begin
        case(i)
            1: atanh_val = 32'h0000_8C9F;
            2: atanh_val = 32'h0000_4162;
            3: atanh_val = 32'h0000_202B;
            4: atanh_val = 32'h0000_1005;
            5: atanh_val = 32'h0000_0800;
            6: atanh_val = 32'h0000_0400;
            7: atanh_val = 32'h0000_0200;
            8: atanh_val = 32'h0000_0100;
            9: atanh_val = 32'h0000_0080;
            10: atanh_val = 32'h0000_0040;
            11: atanh_val = 32'h0000_0020;
            12: atanh_val = 32'h0000_0010;
            13: atanh_val = 32'h0000_0008;
            14: atanh_val = 32'h0000_0004;
            15: atanh_val = 32'h0000_0002;
            16: atanh_val = 32'h0000_0001;
            default: atanh_val = 0;
        endcase
    end

    // CLZ Function
    function [5:0] clz;
        input [31:0] in_val;
        integer k;
        begin
            clz = 0;
            begin : clz_loop
                for (k = 31; k >= 0; k = k - 1) begin
                    if (in_val[k]) disable clz_loop;
                    clz = clz + 1;
                end
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            result <= 0;
            error <= 0;
            done <= 0;
            i <= 1;
            x <= 0; y <= 0; z <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    error <= 0;
                    if (start) state <= S_VALIDATE;
                end

                S_VALIDATE: begin
                    if (a == 0) begin
                        if (b <= 0) begin
                            error <= 1; result <= 32'h7FC00000; state <= S_DONE;
                        end else begin
                            result <= 0; state <= S_DONE;
                        end
                    end else if (a < 0) begin
                        result_is_neg <= b[0]; 
                        abs_a <= -a;
                        state <= S_PREP_LN_CLZ; // Go to new CLZ state
                    end else begin
                        result_is_neg <= 0;
                        abs_a <= a;
                        state <= S_PREP_LN_CLZ; // Go to new CLZ state
                    end
                end

                // ------------------------------------------------
                // 1. Logarithm Prep (Split into 2 cycles)
                // ------------------------------------------------
                S_PREP_LN_CLZ: begin
                    // Cycle 1: Just calculate CLZ
                    shift_count <= clz(abs_a);
                    state <= S_PREP_LN_SHIFT;
                end

                S_PREP_LN_SHIFT: begin
                    // Cycle 2: Shift and Setup Registers
                    current_input = ($unsigned(abs_a) << shift_count) >> 16;
                    x <= current_input + 32'h0001_0000;
                    y <= current_input - 32'h0001_0000;
                    z <= (32 - shift_count) * LN2_FIXED;
                    i <= 1; repeat_done <= 0; 
                    state <= S_CALC_LN;
                end

                S_CALC_LN: begin
                    // CORDIC iteration is usually fast enough for 300MHz 
                    // because it's just Shift + Add/Sub.
                    if (y[31] == 0) begin x_next = x - (y >>> i); y_next = y - (x >>> i); z_next = z + atanh_val; end 
                    else begin x_next = x + (y >>> i); y_next = y + (x >>> i); z_next = z - atanh_val; end
                    x <= x_next; y <= y_next; z <= z_next;

                    if (i <= ITERATIONS) begin
                        if ((i==4||i==13)&&!repeat_done) repeat_done<=1; else begin i<=i+1; repeat_done<=0; end
                    end else begin
                        e_ln2 = (32 - clz(abs_a)) * LN2_FIXED;
                        ln_a_val <= (z <<< 1) - e_ln2;
                        state <= S_MULT_1;
                    end
                end

                // ------------------------------------------------
                // 2. Multiply: P = b * ln(a) (Split)
                // ------------------------------------------------
                S_MULT_1: begin
                    // Cycle 1: Load pipeline registers
                    mult_op_a <= b;
                    mult_op_b <= ln_a_val;
                    state <= S_MULT_2;
                end

                S_MULT_2: begin
                    // Cycle 2: Execute Multiplication
                    // Because inputs are registered, this path starts at Clk edge and ends at Setup.
                    // This creates a clean path for the DSP blocks.
                    mult_result <= mult_op_a * mult_op_b;
                    state <= S_REDUCE_K_1;
                end

                // ------------------------------------------------
                // 3. Range Reduction K (Split)
                // ------------------------------------------------
                S_REDUCE_K_1: begin
                    // Calc k = P * (1/ln2)
                    // Cycle 1: Load inputs
                    // mult_result is Q16.16. We treat it as 64-bit for calculation logic.
                    // But effectively we care about the 32-bit Q16.16 value it represents.
                    // We need to multiply that 32-bit Q16.16 by RECIP (Q16.16).
                    // This generates a Q32.32 result.
                    
                    mult_op_a <= mult_result[31:0]; // The P value (assuming it fits in 32 bits)
                    mult_op_b <= RECIP_LN2;
                    state <= S_REDUCE_K_2;
                end

                S_REDUCE_K_2: begin
                    // Cycle 2: Calc & Extract Integer K
                    
                    temp_mult = mult_op_a * mult_op_b;
                    
                    // Result is Q32.32. Integer part is upper 32 bits.
                    k_integer <= temp_mult >>> 32;
                    
                    // Pass original P to next stage
                    // Store in temporary Z to save a register? No, let's keep it safe.
                    // We need 'mult_result' from earlier. It is still valid.
                    state <= S_REDUCE_R_1;
                end

                // ------------------------------------------------
                // 4. Range Reduction R (Split)
                // ------------------------------------------------
                S_REDUCE_R_1: begin
                    // Calc k * ln2
                    mult_op_a <= k_integer;
                    mult_op_b <= LN2_FIXED;
                    state <= S_REDUCE_R_2;
                end

                S_REDUCE_R_2: begin
                    // Calc mult and subtraction
                    temp_kln2 = mult_op_a * mult_op_b; // Integer * Q16.16 = Q16.16 result in low bits
                    
                    // Final R = P - (k*ln2)
                    z <= mult_result[31:0] - temp_kln2[31:0]; 
                    
                    // Init Exp
                    x <= CORDIC_K; y <= CORDIC_K; i <= 1; repeat_done <= 0; 
                    state <= S_CALC_EXP;
                end

                // ------------------------------------------------
                // 5. Exponential CORDIC
                // ------------------------------------------------
                S_CALC_EXP: begin
                    if (z[31] == 0) begin x_next = x + (y >>> i); y_next = y + (x >>> i); z_next = z - atanh_val; end 
                    else begin x_next = x - (y >>> i); y_next = y - (x >>> i); z_next = z + atanh_val; end
                    x <= x_next; y <= y_next; z <= z_next;
                    if (i <= ITERATIONS) begin
                        if ((i==4||i==13)&&!repeat_done) repeat_done<=1; else begin i<=i+1; repeat_done<=0; end
                    end else begin 
                        state <= S_CONVERT_CLZ; // Go to split convert
                    end
                end

                // ------------------------------------------------
                // 6. Output Conversion (Split)
                // ------------------------------------------------
                S_CONVERT_CLZ: begin
                    // Cycle 1: Abs & CLZ
                    abs_final <= x[31] ? -x : x;
                    state <= S_CONVERT_SHIFT;
                end

                S_CONVERT_SHIFT: begin
                    // Cycle 2: CLZ calculation allowed to settle
                    if (abs_final == 0) begin
                        ieee_comb = 0;
                        state <= S_CONVERT_PACK;
                    end else begin
                        norm_shift <= clz(abs_final);
                        state <= S_CONVERT_PACK;
                    end
                end

                S_CONVERT_PACK: begin
                    // Cycle 3: Barrel Shift & Pack
                    // This separates the Shifter from the CLZ logic
                    if (abs_final == 0) begin
                        ieee_comb = 0;
                    end else begin
                        // Exponent
                        calc_exp = 142 - norm_shift + k_integer;

                        if (calc_exp >= 255) begin
                            error <= 1;
                            ieee_comb = {result_is_neg, 8'hFF, 23'h0}; // Inf
                        end else if (calc_exp <= 0) begin
                            ieee_comb = 0;
                        end else begin
                            ieee_comb[31] = result_is_neg;
                            ieee_comb[30:23] = calc_exp[7:0]; 
                            ieee_comb[22:0]  = (abs_final << norm_shift) >> 8;
                        end
                    end
                    result <= ieee_comb;
                    state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule