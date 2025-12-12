// alu的api接口
// cos alu_cos (
//     .clk(clk),
//     .rst(rst),
//     .start(op_start && (sw_reg == `OP_COS)),
//     .a(a_val),
//     .result(cos_result),
//     .error(cos_error),
//     .done(cos_done)
// );

//具体要求：
//输入：整数角度，范围[-999,999]度
//输出：IEEE754格式的余弦值
//使用11次迭代的CORDIC算法，内部采用Q2.14格式表示角度和结果

`timescale 1ns / 1ps
`include "define.vh"

// ============================================================================
// Module: cos
// Description: Cosine using 11-iter CORDIC, Q2.14 internal, IEEE754 output
// Note: For cosine, we need different angle reduction:
//       cos(θ) = cos(-θ)                  (even function)
//       cos(θ) = -cos(180°-θ)             (quadrant II)
//       cos(θ) = -cos(θ-180°)             (quadrant III)
//       cos(θ) = cos(360°-θ)              (quadrant IV)
// ============================================================================
module cos (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer degrees [-999,999]
    input wire sin_flag, // use for sine module compatibility
    output reg  [`INPUTOUTBIT-1:0] result,     // IEEE754
    output reg  error,
    output reg  done
);
    // Internal signals
    wire deg_to_rad_done, cordic_done, q14_to_float_done;
    wire deg_to_rad_error;
    wire signed [15:0] angle_q14;   // |angle|<=90° after reduction
    wire signed [15:0] cos_q14;     // Cosine value in Q2.14 format
    wire signed [15:0] sin_q14;     // Sine value (not used)
    wire [31:0] float_out;
    reg signed [`INPUTOUTBIT-1:0] a_reg;
    
    // Pipeline control
    reg start_deg_to_rad;
    reg start_cordic;
    reg start_float_conv;
    
    // Angle reduction
    reg signed [15:0] angle_deg_for_cordic; // in degrees, |angle|<=90
    reg need_sign_flip;                     // Flip sign for quadrants II and III
    reg signed [15:0] rdeg;                 // reduced deg for FSM use
    
    // State machine
    reg [2:0] state;
    localparam IDLE       = 3'd0;
    localparam DEG_TO_RAD = 3'd1;
    localparam CORDIC     = 3'd2;
    localparam FLOAT_CONV = 3'd3;
    localparam OUTPUT     = 3'd4;
    
    // Reduce any degree input to [0,360), then to [0,180] with sign flag
    function automatic signed [15:0] reduce_deg_cos(input signed [31:0] deg);
        reg signed [31:0] t;
        begin
            // First reduce to [0, 360)
            t = deg % 360;
            if (t < 0) t = t + 360;
            
            // Now t is in [0, 360)
            // Use symmetry: cos(θ) = cos(360-θ), so we can reduce to [0, 180]
            if (t > 180) t = 360 - t;  // cos(θ) = cos(360-θ)
            reduce_deg_cos = t[15:0];
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
    
    // Instantiate CORDIC core for COS calculation (MODE=1)
    cordic_core #(.MODE(1)) u_cordic (  // MODE 1 = COS
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(angle_q14),
        .result_q14(cos_q14),      // Cosine output
        .secondary_q14(sin_q14),   // Sine output (not used)
        .cordic_valid(),
        .done(cordic_done)
    );
    
    q14_to_float u_float_conv (
        .clk(clk),
        .rst(rst),
        .start(start_float_conv),
        .q14_value(need_sign_flip ? -cos_q14 : cos_q14), // apply sign if needed
        .float_result(float_out),
        .convert_valid(),
        .done(q14_to_float_done)
    );
    
    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_sync      <= 1'b0;
            sin_flag_sync   <= 1'b0;
            a_sync          <= 0;
            state           <= IDLE;
            start_deg_to_rad<= 0;
            start_cordic    <= 0;
            start_float_conv<= 0;
            result          <= 0;
            error           <= 0;
            done            <= 0;
            need_sign_flip  <= 0;
            angle_deg_for_cordic <= 0;
            rdeg            <= 0;
        end else begin
            // input staging to break long path
            start_sync    <= start;
            sin_flag_sync <= sin_flag;
            a_sync        <= a;

            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_float_conv <= 0;

            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start_sync) begin
                        if (a_sync > 999 || a_sync < -999) begin
                            error  <= 1;
                            result <= 32'hFFC00000; // NaN
                            done   <= 1;
                        end else begin
                            a_reg = sin_flag_sync ? a_sync - 90 : a_sync;
                            rdeg  = reduce_deg_cos(a_reg);
                            if (rdeg <= 90) begin
                                angle_deg_for_cordic <= rdeg;
                                need_sign_flip <= 1'b0;
                            end else begin
                                angle_deg_for_cordic <= 180 - rdeg;
                                need_sign_flip <= 1'b1;
                            end
                            start_deg_to_rad <= 1;
                            state            <= DEG_TO_RAD;
                        end
                    end
                end
                
                DEG_TO_RAD: begin
                    if (deg_to_rad_done) begin
                        if (deg_to_rad_error) begin
                            error  <= 1;
                            result <= 32'hFFC00000;
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
                        start_float_conv <= 1;
                        state            <= FLOAT_CONV;
                    end
                end
                
                FLOAT_CONV: begin
                    if (q14_to_float_done) begin
                        result <= float_out;
                        state  <= OUTPUT;
                    end
                end
                
                OUTPUT: begin
                    done  <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
    
endmodule