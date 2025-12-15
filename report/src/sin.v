`timescale 1ns / 1ps
`include "define.vh"

// ============================================================================
// Module: sin
// Description: Sine using 11-iter CORDIC, Q2.14 internal, IEEE754 output
// ============================================================================
module sin (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer degrees [-999,999]
    output reg  [`INPUTOUTBIT-1:0] result,     // IEEE754
    output reg  error,
    output reg  done
);
    // Internal signals
    wire deg_to_rad_done, cordic_done, q14_to_float_done;
    wire deg_to_rad_error;
    wire signed [15:0] angle_q14;   // |angle|<=90 after reduction
    wire signed [15:0] sin_q14;
    wire signed [15:0] cos_q14;
    wire [31:0] float_out;

    // Pipeline control
    reg start_deg_to_rad;
    reg start_cordic;
    reg start_float_conv;

    // Angle reduction
    reg signed [15:0] angle_deg_for_cordic; // in degrees, |angle|<=90
    reg need_sign_flip;                     // Q2/Q3 flip
    reg signed [15:0] rdeg;                 // reduced deg for FSM use

    // State machine
    reg [2:0] state;
    localparam IDLE       = 3'd0;
    localparam DEG_TO_RAD = 3'd1;
    localparam CORDIC     = 3'd2;
    localparam FLOAT_CONV = 3'd3;
    localparam OUTPUT     = 3'd4;

    // Reduce any degree input to [-180,180], then to [-90,90] with sign flag
    function automatic signed [15:0] reduce_deg(input signed [31:0] deg);
        reg signed [31:0] t;
        begin
            t = deg % 360;                 // wrap to [-359,359]
            if (t > 180)      t = t - 360; // now in [-180,180]
            else if (t < -180) t = t + 360;
            reduce_deg = t[15:0];
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

    cordic_core #(.MODE(0)) u_cordic (  // SIN
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(angle_q14),
        .result_q14(sin_q14),
        .secondary_q14(cos_q14),
        .cordic_valid(),
        .done(cordic_done)
    );

    q14_to_float u_float_conv (
        .clk(clk),
        .rst(rst),
        .start(start_float_conv),
        .q14_value(need_sign_flip ? -sin_q14 : sin_q14), // apply quadrant sign
        .float_result(float_out),
        .convert_valid(),
        .done(q14_to_float_done)
    );

    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= IDLE;
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_float_conv <= 0;
            result           <= 0;
            error            <= 0;
            done             <= 0;
            need_sign_flip   <= 0;
            angle_deg_for_cordic <= 0;
            rdeg             <= 0;
        end else begin
            // start_deg_to_rad <= 0;
            // start_cordic     <= 0;
            // start_float_conv <= 0;
            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start) begin
                        if (a > 999 || a < -999) begin
                            error  <= 1;
                            result <= 32'hFFC00000; // NaN
                            done   <= 1;
                        end else begin
                            // Angle reduction
                            rdeg = reduce_deg(a);
                            if (rdeg > 90) begin                 // Quadrant II
                                angle_deg_for_cordic <= 180 - rdeg; // [0,90]
                                need_sign_flip       <= 1'b1;
                            end else if (rdeg < -90) begin        // Quadrant III
                                angle_deg_for_cordic <= 180 + rdeg; // [0,90]
                                need_sign_flip       <= 1'b1;
                            end else begin                        // Quadrant I/IV
                                angle_deg_for_cordic <= rdeg;
                                need_sign_flip       <= 1'b0;
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