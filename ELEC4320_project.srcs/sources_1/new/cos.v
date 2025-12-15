//`define INPUTOUTBIT 16
// cos alu_cos (
//     .clk(clk),
//     .rst(rst),
//     .start(op_start && (sw_reg == `OP_COS || sw_reg == `OP_SIN)),
//     .a( sw_reg == `OP_SIN ? (a_val - 16'sd90) : a_val ), // sin(x)=cos(x-90)
//     .result(cos_result),
//     .error(cos_error),
//     .done(cos_done),
// );

//具体要求：
//输入：整数角度，范围[-999,999]度
//输出：BF16格式的余弦值
//使用11次迭代的CORDIC算法，内部采用Q2.14格式表示角度和结果
//现在都是直接当cos去实现就可以了

`timescale 1ns / 1ps
`include "define.vh"

// ============================================================================
// Module: cos
// Description: Cosine using 11-iter CORDIC, Q2.14 internal, BF16 output
//              上层如需计算正弦，请先在外部将角度 a 减去 90° 后再传入.
// ============================================================================
module cos (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer degrees [-999,999]
    output reg  [`INPUTOUTBIT-1:0] result,     // BF16
    output reg  error,
    output reg  done
);
    // Internal signals
    wire deg_to_rad_done, cordic_done, q14_to_bf16_done;
    wire deg_to_rad_error;
    wire signed [15:0] angle_q14;   // |angle|<=90° after reduction
    wire signed [15:0] cos_q14;     // Cosine value in Q2.14 format
    wire [15:0] bf16_out;           // BF16 output

    // Pipeline control
    reg start_deg_to_rad;
    reg start_cordic;
    reg start_bf16_conv;

    // Angle reduction
    reg signed [15:0] a_reg;                // latched angle
    reg signed [15:0] angle_deg_for_cordic; // in degrees, |angle|<=90
    reg need_sign_flip;                     // flip sign for quadrants II
    reg signed [15:0] rdeg;                 // reduced deg for FSM use

    // State machine
    reg [3:0] state;  // Expanded to 4 bits for additional states
    localparam IDLE         = 4'd0;
    localparam REDUCE_ANGLE = 4'd1;  // NEW: Pipelined angle reduction (cycle 1)
    localparam MAP_ANGLE    = 4'd2;  // NEW: Map to [0,90] (cycle 2)
    localparam DEG_TO_RAD   = 4'd3;
    localparam CORDIC       = 4'd4;
    localparam BF16_CONV    = 4'd5;
    localparam OUTPUT       = 4'd6;
    
    // NEW: Register for pipelined angle reduction
    reg signed [15:0] rdeg;  // Reduced angle [0,180]

    // Reduce any degree input to [0,360), then to [0,180] with sign flag
    function automatic signed [15:0] reduce_deg_cos(input signed [15:0] deg);
        reg signed [15:0] t;
        begin
            t = deg % 16'sd360;
            if (t < 0) t = t + 16'sd360;
            if (t > 16'sd180) t = 16'sd360 - t;
            reduce_deg_cos = t;
        end
    endfunction

    // Modules
    deg_to_rad u_deg_to_rad (
        .clk(clk),
        .rst(rst),
        .start(start_deg_to_rad),
        .angle_deg(angle_deg_for_cordic),
        .angle_q14(angle_q14),
        .angle_valid(),          // unused
        .error(deg_to_rad_error),
        .done(deg_to_rad_done)
    );

    // CORDIC core for COS calculation
    // 0: begin // SIN: result = sin, secondary = cos
    //    result_q14     = sin_val;
    //    secondary_q14  = cos_val;
    // end
    cordic_core #(.MODE(0)) u_cordic (
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(angle_q14),
        .result_q14(),      
        .secondary_q14(cos_q14),    
        .cordic_valid(),
        .done(cordic_done)
    );


    // Q2.14 -> BF16
    Q14_to_BF16 u_bf16_conv (
        .clk(clk),
        .rst(rst),
        .start(start_bf16_conv),
        .q14_value(need_sign_flip ? -cos_q14 : cos_q14),
        .float_result(bf16_out),
        .convert_valid(),
        .done(q14_to_bf16_done)
    );

    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= IDLE;
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_bf16_conv  <= 0;
            result           <= 0;
            error            <= 0;
            done             <= 0;
            need_sign_flip   <= 0;
            angle_deg_for_cordic <= 0;
            rdeg             <= 0;
            a_reg            <= 0;
        end else begin
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_bf16_conv  <= 0;

            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start) begin
                        if (a > 16'sd9999 || a < -16'sd9999) begin
                            error  <= 1;
                            result <= 16'hFFC0; // BF16 NaN
                            done   <= 1;
                        end else begin
                            a_reg <= a;  // Store input, will be processed next cycle
                            state <= REDUCE_ANGLE;
                        end
                    end
                end
                
                // NEW: Pipelined angle reduction (break sw_reg fanout path)
                REDUCE_ANGLE: begin
                    // Cycle 1: Compute rdeg from a_reg (registered reduce_deg_cos)
                    rdeg <= reduce_deg_cos(a_reg);
                    state <= MAP_ANGLE;
                end

                // NEW: Map angle to [0,90] range
                MAP_ANGLE: begin
                    // Cycle 2: Use rdeg to compute angle mapping (now using registered rdeg, not sw_reg)
                    if (rdeg <= 16'sd90) begin
                        angle_deg_for_cordic <= rdeg;
                        need_sign_flip       <= 1'b0;
                    end else begin
                        angle_deg_for_cordic <= 16'sd180 - rdeg; // (90,180] -> [0,90]
                        need_sign_flip       <= 1'b1;            // cos negative in Q2
                    end
                    start_deg_to_rad <= 1;
                    state            <= DEG_TO_RAD;
                end

                DEG_TO_RAD: begin
                    if (deg_to_rad_done) begin
                        if (deg_to_rad_error) begin
                            error  <= 1;
                            result <= 16'hFFC0; // BF16 NaN
                            done   <= 1;
                            state  <= IDLE;
                        end else begin
                            start_cordic <= 1;
                            state        <= CORDIC;
                        end
                    end
                end

                CORDIC: begin
                    if (cordic_done) begin
                        start_bf16_conv <= 1;
                        state           <= BF16_CONV;
                    end
                end

                BF16_CONV: begin
                    if (q14_to_bf16_done) begin
                        result <= bf16_out;
                        state  <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule