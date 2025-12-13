//`define INPUTOUTBIT 16
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
//输入：整数角度，范围[-999,999]度，但不检查输入范围
//输出：BF16格式的正切值
//先将输入的角度映射到[-pi/2,pi/2]的范围，确保tan值和映射之前一致
//然后考虑如果输入是90度或-90度时，输出error
//使用11次迭代的CORDIC算法，内部采用Q2.14格式表示角度和结果
//CORDIC模式选择为0，然后同时获取sin和cos，
//然后分别把sin和cos换算成BF16，然后才进行除法得到tan
//最后tan的结果要保持BF16格式
//需要运行在300Mhz，可以调用DSP，但是不可以用IP和直接用LUT

`timescale 1ns / 1ps
`include "define.vh"

module tan (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer degrees [-999,999]
    output reg  [`INPUTOUTBIT-1:0] result,     // BF16 output
    output reg  error,
    output reg  done
);
    // Internal signals
    wire deg_to_rad_done, cordic_done, sin_bf16_done, cos_bf16_done, bf16_div_done;
    wire deg_to_rad_error, bf16_div_error;
    wire signed [15:0] angle_q14;
    wire signed [15:0] sin_q14, cos_q14;
    wire [15:0] sin_bf16, cos_bf16;
    wire [15:0] tan_bf16;

    // Pipeline control
    reg start_deg_to_rad;
    reg start_cordic;
    reg start_sin_bf16;
    reg start_cos_bf16;
    reg start_bf16_div;

    // Angle reduction
    reg signed [15:0] reduced_deg;      // |angle|<=90
    reg result_sign;                    // Final sign of tan result
    wire signed [15:0] reduced_now;

    // State machine
    reg [3:0] state;
    localparam IDLE        = 4'd0;
    localparam REDUCE      = 4'd1;
    localparam DEG_TO_RAD  = 4'd2;
    localparam CORDIC      = 4'd3;
    localparam CONV_SIN    = 4'd4;
    localparam CONV_COS    = 4'd5;
    localparam BF16_DIV    = 4'd6;
    localparam OUTPUT      = 4'd7;

    // cos ≈ 0 判定阈值（Q2.14）
    localparam signed [15:0] COS_MIN = 16'sd16; // ~0.001 in Q2.14

    // Improved angle reduction function
    function automatic signed [15:0] reduce_angle_tan;
        input signed [15:0] deg;
        reg signed [15:0] t;
        begin
            // Reduce to [-180, 180]
            t = deg % 16'sd360;
            if (t > 16'sd180)  t = t - 16'sd360;
            if (t < -16'sd180) t = t + 16'sd360;
            
            // Reduce to [-90, 90] using tan periodicity
            if (t > 16'sd90) begin
                t = t - 16'sd180;
            end else if (t < -16'sd90) begin
                t = t + 16'sd180;
            end
            
            // Special case: 90 and -90 degrees
            if (t == 16'sd90) t = 16'sd90;  // Will be caught as error
            if (t == -16'sd90) t = 16'sd90; // Will be caught as error
            
            reduce_angle_tan = t;
        end
    endfunction
    
    assign reduced_now = reduce_angle_tan(a);

    function automatic [15:0] abs16;
        input signed [15:0] v;
        abs16 = v[15] ? (~v + 16'd1) : v;
    endfunction

    // 角度转换
    deg_to_rad u_deg_to_rad (
        .clk(clk),
        .rst(rst),
        .start(start_deg_to_rad),
        .angle_deg(reduced_deg),
        .angle_q14(angle_q14),
        .angle_valid(),
        .error(deg_to_rad_error),
        .done(deg_to_rad_done)
    );

    // CORDIC 求 sin/cos
    cordic_core #(.MODE(0)) u_cordic (
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(angle_q14),
        .result_q14(sin_q14),
        .secondary_q14(cos_q14),
        .cordic_valid(),
        .done(cordic_done)
    );

    // Q2.14 -> BF16
    Q14_to_BF16 u_sin_bf16 (
        .clk(clk),
        .rst(rst),
        .start(start_sin_bf16),
        .q14_value(sin_q14),
        .float_result(sin_bf16),
        .convert_valid(),
        .done(sin_bf16_done)
    );

    Q14_to_BF16 u_cos_bf16 (
        .clk(clk),
        .rst(rst),
        .start(start_cos_bf16),
        .q14_value(cos_q14),
        .float_result(cos_bf16),
        .convert_valid(),
        .done(cos_bf16_done)
    );

    // BF16 除法
    bf16_divider u_bf16_div (
        .clk(clk),
        .rst(rst),
        .start(start_bf16_div),
        .a(result_sign ? {1'b1, sin_bf16[14:0]} : sin_bf16), // Apply sign here
        .b(cos_bf16),
        .result(tan_bf16),
        .error(bf16_div_error),
        .done(bf16_div_done)
    );

    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= IDLE;
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_sin_bf16   <= 0;
            start_cos_bf16   <= 0;
            start_bf16_div   <= 0;
            result           <= 0;
            error            <= 0;
            done             <= 0;
            result_sign      <= 0;
            reduced_deg      <= 0;
        end else begin
            // Default control signals
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_sin_bf16   <= 0;
            start_cos_bf16   <= 0;
            start_bf16_div   <= 0;
            done             <= 0;
            error            <= error; // 保持错误标志，避免被清零

            case (state)
                IDLE: begin
                    error <= 0; // 清零错误，仅在新一轮开始
                    if (start) state <= REDUCE;
                end

                REDUCE: begin
                    if (reduced_now == 16'sd90 || reduced_now == -16'sd90) begin
                        error  <= 1;
                        result <= 16'hFFC0; // BF16 NaN
                        done   <= 1;
                        state  <= IDLE;
                    end else begin
                        reduced_deg <= abs16(reduced_now);
                        result_sign <= (reduced_now < 0);
                        start_deg_to_rad <= 1;
                        state <= DEG_TO_RAD;
                    end
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
                            state <= CORDIC;
                        end
                    end
                end

                CORDIC: begin
                    if (cordic_done) begin
                        if (abs16(cos_q14) <= COS_MIN) begin
                            error  <= 1;
                            result <= 16'hFFC0; // BF16 NaN
                            state  <= OUTPUT;
                        end else begin
                            start_sin_bf16 <= 1;
                            start_cos_bf16 <= 1;
                            state <= CONV_SIN;
                        end
                    end
                end

                CONV_SIN: begin
                    if (sin_bf16_done) state <= CONV_COS;
                end

                CONV_COS: begin
                    if (cos_bf16_done) begin
                        start_bf16_div <= 1;
                        state <= BF16_DIV;
                    end
                end

                BF16_DIV: begin
                    if (bf16_div_done) begin
                        if (bf16_div_error) begin
                            error  <= 1;
                            result <= 16'hFFC0; // BF16 NaN
                        end else begin
                            result <= tan_bf16;
                        end
                        state <= OUTPUT;
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