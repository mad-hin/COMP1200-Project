//     arctan alu_atan (
//         .clk(clk),
//         .rst(rst),
//         .start(op_start && (sw_reg == `OP_ATAN)),
//         .a(a_val),
//         .result(atan_result),
//         .error(atan_error),
//         .done(atan_done)
//     );

// Requirements:
// - When a = 0, output 0 degrees.
// - arctan(1) = 45 degrees, arctan(-1) = -45 degrees.
// - For |a| > 1:
// - CORDIC requires y <= x. If x = 1 and y = 1/a, CORDIC computes arctan(y/x) = arctan(1/a).
// - Input: integer slope in range [-999, 999] (range is not strictly checked here).
// - Output: angle in BF16 format.
// - Flow:
//     1) Check a equals -1, 0, or 1 and return directly via if-else.
//     2) Otherwise, apply the above identity based on the sign.
// - Use an 11-iteration CORDIC algorithm, internal angle/result in Q2.14 format.
// - CORDIC mode = 1 (arctan), which can compute arctan(1/a) directly.
// - Must run at 300 MHz. DSPs may be used, but no IP cores and no direct LUT-only implementations.

`timescale 1ns / 1ps
`include "define.vh"

module arctan (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer slope [-999,999]
    output reg  [`INPUTOUTBIT-1:0] result,     // BF16 angle in degrees
    output reg  error,
    output reg  done
);
    // ============================================================================
    // Constants
    // ============================================================================
    localparam BF16_45      = 16'h4234;  // 45.0 in BF16
    localparam BF16_NEG_45  = 16'hC234;  // -45.0 in BF16
    localparam BF16_ZERO    = 16'h0000;  // 0.0 in BF16
    localparam BF16_NAN     = 16'h7FC0;  // qNaN in BF16 (sign doesn't matter)

    localparam signed [15:0] PI_OVER_2_Q14 = 16'h3244;

    // ============================================================================
    // Internal Signals
    // ============================================================================
    reg [3:0] state;
    localparam IDLE           = 4'd0;
    localparam CHECK_SPECIAL  = 4'd1;
    localparam PREPARE_INPUT  = 4'd2;
    localparam CORDIC_CALC    = 4'd3;
    localparam ADJUST_RESULT  = 4'd4;
    localparam RAD_TO_DEG     = 4'd5;
    localparam BF16_START     = 4'd6;
    localparam OUTPUT         = 4'd7;

    reg signed [15:0] a_reg;             // Latched input
    reg signed [15:0] cordic_input_q14;  // 1/|a| in Q2.14
    reg signed [15:0] cordic_result_q14; // atan(1/|a|) in Q2.14 (rad)
    reg signed [15:0] angle_q14;         // Final angle in Q2.14 (rad)
    reg signed [15:0] deg_q14;           // Angle in Q2.14 (deg)
    reg use_complement;                  // Always 1 for |a|>1, kept for clarity
    reg result_sign;                     // 1 if final angle is negative
    reg start_bf16;                      // Pulse to start BF16 conversion
    reg start_cordic;                    // Pulse to start CORDIC

    // Module instances
    wire cordic_done;
    wire signed [15:0] cordic_result;
    wire signed [15:0] cordic_secondary;
    wire cordic_valid;

    wire rad_to_deg_done;
    wire signed [15:0] deg_q14_wire;

    wire bf16_conv_done;
    wire [15:0] bf16_result;

    // ============================================================================
    // CORDIC Instance (Mode 1 for arctan)
    // ============================================================================
    cordic_core #(
        .MODE(1),           // Mode 1: ARCTAN mode
        .ITERATIONS(11)     // 11 iterations as specified
    ) u_cordic (
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(cordic_input_q14),     // Input in Q2.14
        .result_q14(cordic_result),       // arctan(1/x) in Q2.14 radians
        .secondary_q14(cordic_secondary), // x_final, not used
        .cordic_valid(cordic_valid),
        .done(cordic_done)
    );

    // ============================================================================
    // Radians to Degrees Converter
    // ============================================================================
    rad_to_deg u_rad_to_deg (
        .clk(clk),
        .rst(rst),
        .start(state == RAD_TO_DEG),
        .rad_q14(angle_q14),            // Input radians in Q2.14
        .deg_q14(deg_q14_wire),         // Output degrees in Q2.14
        .done(rad_to_deg_done)
    );

    // ============================================================================
    // Q2.14 to BF16 Converter
    // ============================================================================
    Q14_to_BF16 u_bf16_conv (
        .clk(clk),
        .rst(rst),
        .start(start_bf16),
        .q14_value(deg_q14),           // Input in Q2.14 format
        .float_result(bf16_result),    // Output in BF16 format
        .convert_valid(),
        .done(bf16_conv_done)
    );

    // ============================================================================
    // Main State Machine
    // ============================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            result <= 0;
            error <= 0;
            done <= 0;
            a_reg <= 0;
            cordic_input_q14 <= 0;
            cordic_result_q14 <= 0;
            angle_q14 <= 0;
            deg_q14 <= 0;
            use_complement <= 0;
            result_sign <= 0;
            start_bf16 <= 0;
            start_cordic <= 0;
        end else begin
            start_bf16  <= 0; // default deassert
            start_cordic<= 0;
            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start) begin
                        a_reg <= a;
                        state <= CHECK_SPECIAL;
                    end
                end

                CHECK_SPECIAL: begin
                    // Special cases: -1, 0, 1
                    if (a_reg == 0) begin
                        result <= BF16_ZERO;
                        done   <= 1;
                        state  <= IDLE;
                    end else if (a_reg == 1) begin
                        result <= BF16_45;
                        done   <= 1;
                        state  <= IDLE;
                    end else if (a_reg == -1) begin
                        result <= BF16_NEG_45;
                        done   <= 1;
                        state  <= IDLE;
                    end else begin
                        // For any other integer, |a| > 1
                        if (a_reg > 0) begin
                            cordic_input_q14 <= 16'd16384 / a_reg;    // 1/a in Q2.14
                            result_sign      <= 0;                    // positive result
                        end else begin
                            cordic_input_q14 <= 16'd16384 / (-a_reg); // 1/|a|
                            result_sign      <= 1;                    // negative result
                        end
                        use_complement <= 1'b1;
                        state <= PREPARE_INPUT;
                    end
                end

                PREPARE_INPUT: begin
                    start_cordic <= 1'b1;      // Single-cycle pulse to start CORDIC
                    state        <= CORDIC_CALC;
                end

                CORDIC_CALC: begin
                    if (cordic_done) begin
                        cordic_result_q14 <= cordic_result;
                        state <= ADJUST_RESULT;
                    end
                end

                ADJUST_RESULT: begin
                    // For |a| > 1:
                    if (result_sign)
                        angle_q14 <= -PI_OVER_2_Q14 - cordic_result_q14;
                    else
                        angle_q14 <=  PI_OVER_2_Q14 - cordic_result_q14;
                    state <= RAD_TO_DEG;
                end

                RAD_TO_DEG: begin
                    if (rad_to_deg_done) begin
                        deg_q14 <= deg_q14_wire;  // latch first
                        state   <= BF16_START;
                    end
                end

                BF16_START: begin
                    start_bf16 <= 1'b1;  // Start BF16 conversion on next cycle; input stable
                    state      <= OUTPUT;
                end

                OUTPUT: begin
                    if (bf16_conv_done) begin
                        result <= bf16_result; // sign already encoded from deg_q14
                        done   <= 1;
                        state  <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

// ============================================================================
// Radians to Degrees Converter Module
// ============================================================================
module rad_to_deg (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [15:0] rad_q14,  // Input radians in Q2.14
    output reg signed [15:0] deg_q14,  // Output degrees in Q2.14
    output reg done
);
    
    localparam signed [31:0] RAD_TO_DEG_SCALE = 32'd58668; 
    
    reg [2:0] state, next_state;
    localparam IDLE=3'd0, MUL1=3'd1, MUL2=3'd2, MUL3=3'd3, SHIFT=3'd4, OUTPUT_ST=3'd5;
    
    reg signed [31:0] temp;
    reg signed [31:0] temp_reg;
    reg signed [15:0] rad_reg;
    reg signed [15:0] rad_reg2;
    
    // State register
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end
    
    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (start) next_state = MUL1;
            MUL1:      next_state = MUL2;
            MUL2:      next_state = MUL3;
            MUL3:      next_state = SHIFT;
            SHIFT:     next_state = OUTPUT_ST;
            OUTPUT_ST: next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end
    
    // Datapath
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            deg_q14  <= 0;
            done     <= 0;
            temp     <= 0;
            temp_reg <= 0;
            rad_reg  <= 0;
            rad_reg2 <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    if (start) rad_reg <= rad_q14;
                end
                
                MUL1: begin
                    rad_reg2 <= rad_reg;
                    temp     <= rad_reg * RAD_TO_DEG_SCALE;
                end
                
                MUL2: begin
                    temp_reg <= temp;
                end
                
                MUL3: begin
                    // Delay stage for multiplication stability
                end
                
                SHIFT: begin
                    deg_q14 <= temp_reg[25:10];  // >>10 to keep 16 bits
                end
                
                OUTPUT_ST: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule