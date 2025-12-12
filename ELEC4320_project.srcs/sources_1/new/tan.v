    // tan alu_tan (
    //     .clk(clk),
    //     .rst(rst),
    //     .start(op_start && (sw_reg == `OP_TAN)),
    //     .a(a_val),
    //     .result(tan_result),
    //     .error(tan_error),
    //     .done(tan_done)
    // );

    //具体要求：
//输入：整数角度，范围[-999,999]度
//输出：IEEE754格式的正切值
//使用11次迭代的CORDIC算法，内部采用Q2.14格式表示角度和结果
//当输入是90度或-90度时，输出error

`timescale 1ns / 1ps
`include "define.vh"

// ============================================================================
// Module: tan
// Description: Tangent using 11-iter CORDIC, Q2.14 internal, IEEE754 output
// Input: Integer angle in degrees [-999,999]
// Special: if angle ≡ ±90° (mod 180) => error
// ============================================================================
module tan (
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
    wire signed [15:0] angle_q14;
    wire signed [15:0] tan_q14;
    wire signed [15:0] cos_q14;
    wire [31:0] float_out;

    // Pipeline control
    reg start_deg_to_rad;
    reg start_cordic;
    reg start_float_conv;

    // Angle reduction and sign handling
    reg signed [15:0] reduced_deg;  // in (0,90] after abs, <=90
    reg need_sign_flip;             // flip for negative input
    reg is_90_degree;               // flag for ±90°

    // State machine
    reg [2:0] state;
    localparam IDLE       = 3'd0;
    localparam DEG_TO_RAD = 3'd1;
    localparam CORDIC     = 3'd2;
    localparam FLOAT_CONV = 3'd3;
    localparam OUTPUT     = 3'd4;

    // Custom modulo for 180 that handles negatives, result in [-179,179]
    function automatic signed [31:0] mod_180(input signed [31:0] deg);
        reg signed [31:0] r;
        begin
            r = deg % 180;
            if (r > 179)      r = r - 180;
            else if (r < -179) r = r + 180;
            mod_180 = r;
        end
    endfunction

    // Reduce degree to (-90,90) and detect ±90°
    task reduce_and_check_tan;
        input  signed [31:0] deg;
        output reg signed [15:0] out_deg;
        output reg is_90;
        output reg sign_flip;
        reg signed [31:0] mod_result;
        begin
            is_90     = 0;
            sign_flip = 0;
            out_deg   = 0;

            mod_result = mod_180(deg);

            if (mod_result == 90 || mod_result == -90) begin
                is_90 = 1;
            end else begin
                // map to (-90,90)
                if (mod_result > 90)        out_deg = mod_result - 180;
                else if (mod_result <= -90) out_deg = mod_result + 180;
                else                        out_deg = mod_result;
                if (out_deg < 0) begin
                    out_deg   = -out_deg;
                    sign_flip = 1;
                end
            end
        end
    endtask

    // Modules
    deg_to_rad u_deg_to_rad (
        .clk(clk),
        .rst(rst),
        .start(start_deg_to_rad),
        .angle_deg(reduced_deg),
        .angle_q14(angle_q14),
        .angle_valid(),          // unused
        .error(deg_to_rad_error),
        .done(deg_to_rad_done)
    );

    cordic_core #(.MODE(2)) u_cordic (  // TAN
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(angle_q14),
        .result_q14(tan_q14),
        .secondary_q14(cos_q14),
        .cordic_valid(),
        .done(cordic_done)
    );

    q14_to_float u_float_conv (
        .clk(clk),
        .rst(rst),
        .start(start_float_conv),
        .q14_value(need_sign_flip ? -tan_q14 : tan_q14),
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
            reduced_deg      <= 0;
            is_90_degree     <= 0;
        end else begin
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_float_conv <= 0;
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
                            reduce_and_check_tan(a, reduced_deg, is_90_degree, need_sign_flip);
                            if (is_90_degree) begin
                                error  <= 1;
                                result <= 32'hFFC00000;
                                done   <= 1;
                            end else begin
                                start_deg_to_rad <= 1;
                                state            <= DEG_TO_RAD;
                            end
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