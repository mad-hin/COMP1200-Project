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

    // 优化的角度缩减寄存器
    reg signed [15:0] reduced_deg_reg;      // |angle|<=90
    reg result_sign_reg;                    // Final sign of tan result
    reg [15:0] abs_a;                       // |a|
    
    // 优化：分阶段的角度缩减流水线
    reg [15:0] phase1_reduced;  // 第一阶段缩减结果 [-360,360]
    reg [15:0] phase2_reduced;  // 第二阶段缩减结果 [-180,180]
    reg phase1_valid, phase2_valid;
    
    // 优化：增加流水线寄存器
    reg signed [15:0] angle_q14_reg;
    reg signed [15:0] sin_q14_reg, cos_q14_reg;
    reg [15:0] sin_bf16_reg, cos_bf16_reg;
    
    // State machine - 扩展状态以支持流水线
    reg [4:0] state;
    localparam IDLE        = 5'd0;
    localparam REDUCE_P1   = 5'd1;  // 第一阶段角度缩减
    localparam REDUCE_P2   = 5'd2;  // 第二阶段角度缩减
    localparam REDUCE_FIN  = 5'd3;  // 角度缩减完成检查
    localparam DEG_TO_RAD  = 5'd4;
    localparam CORDIC      = 5'd5;
    localparam CONV_SIN    = 5'd6;
    localparam CONV_COS    = 5'd7;
    localparam BF16_DIV    = 5'd8;
    localparam OUTPUT      = 5'd9;

    // cos ≈ 0 判定阈值（Q2.14）
    localparam signed [15:0] COS_MIN = 16'sd16; // ~0.001 in Q2.14

    // 优化的绝对值函数 - 减少关键路径
    function [15:0] fast_abs16;
        input signed [15:0] v;
        begin
            fast_abs16 = v[15] ? (~v + 1'b1) : v;
        end
    endfunction

    // 优化：流水线式角度缩减函数 - 第一阶段：缩减到[-360,360]
    function [15:0] reduce_phase1;
        input signed [15:0] deg;
        reg signed [15:0] temp;
        begin
            temp = deg;
            // 使用循环展开的减法，避免取模运算
            if (temp > 360) begin
                if (temp > 720) temp = temp - 720;
                if (temp > 360) temp = temp - 360;
            end else if (temp < -360) begin
                if (temp < -720) temp = temp + 720;
                if (temp < -360) temp = temp + 360;
            end
            reduce_phase1 = temp;
        end
    endfunction

    // 优化：流水线式角度缩减函数 - 第二阶段：缩减到[-180,180]
    function [15:0] reduce_phase2;
        input signed [15:0] deg;
        reg signed [15:0] temp;
        begin
            temp = deg;
            if (temp > 180) temp = temp - 360;
            else if (temp < -180) temp = temp + 360;
            reduce_phase2 = temp;
        end
    endfunction

    // 角度转换
    deg_to_rad u_deg_to_rad (
        .clk(clk),
        .rst(rst),
        .start(start_deg_to_rad),
        .angle_deg(reduced_deg_reg),
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
        .angle_q14(angle_q14_reg),
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
        .q14_value(sin_q14_reg),
        .float_result(sin_bf16),
        .convert_valid(),
        .done(sin_bf16_done)
    );

    Q14_to_BF16 u_cos_bf16 (
        .clk(clk),
        .rst(rst),
        .start(start_cos_bf16),
        .q14_value(cos_q14_reg),
        .float_result(cos_bf16),
        .convert_valid(),
        .done(cos_bf16_done)
    );

    // BF16 除法 - 需要确保该模块本身能运行在300MHz
    bf16_divider u_bf16_div (
        .clk(clk),
        .rst(rst),
        .start(start_bf16_div),
        .a({result_sign_reg, sin_bf16_reg[14:0]}), // 直接带符号处理
        .b(cos_bf16_reg),
        .result(tan_bf16),
        .error(bf16_div_error),
        .done(bf16_div_done)
    );

    // FSM - 优化后的流水线状态机
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
            result_sign_reg  <= 0;
            reduced_deg_reg  <= 0;
            abs_a            <= 0;
            phase1_reduced   <= 0;
            phase2_reduced   <= 0;
            phase1_valid     <= 0;
            phase2_valid     <= 0;
            angle_q14_reg    <= 0;
            sin_q14_reg      <= 0;
            cos_q14_reg      <= 0;
            sin_bf16_reg     <= 0;
            cos_bf16_reg     <= 0;
        end else begin
            // Default control signals
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_sin_bf16   <= 0;
            start_cos_bf16   <= 0;
            start_bf16_div   <= 0;
            done             <= 0;
            
            // 流水线寄存器更新
            if (deg_to_rad_done) begin
                angle_q14_reg <= angle_q14;
            end
            
            if (cordic_done) begin
                sin_q14_reg <= sin_q14;
                cos_q14_reg <= cos_q14;
            end
            
            if (sin_bf16_done) begin
                sin_bf16_reg <= sin_bf16;
            end
            
            if (cos_bf16_done) begin
                cos_bf16_reg <= cos_bf16;
            end

            case (state)
                IDLE: begin
                    error <= 0;
                    if (start) begin
                        abs_a <= fast_abs16(a);
                        result_sign_reg <= a[15]; // 保存符号
                        state <= REDUCE_P1;
                    end
                end

                REDUCE_P1: begin
                    // 第一阶段角度缩减（1周期）
                    phase1_reduced <= reduce_phase1(a);
                    state <= REDUCE_P2;
                end

                REDUCE_P2: begin
                    // 第二阶段角度缩减（1周期）
                    phase2_reduced <= reduce_phase2(phase1_reduced);
                    state <= REDUCE_FIN;
                end

                REDUCE_FIN: begin
                    // 检查是否为90度或-90度
                    if (phase2_reduced == 16'sd90 || phase2_reduced == -16'sd90) begin
                        error  <= 1;
                        result <= 16'hFFC0; // BF16 NaN
                        done   <= 1;
                        state  <= IDLE;
                    end else begin
                        // 调整到[-90,90]范围
                        if (phase2_reduced > 16'sd90) begin
                            reduced_deg_reg <= phase2_reduced - 16'sd180;
                            result_sign_reg <= ~result_sign_reg; // 符号翻转
                        end else if (phase2_reduced < -16'sd90) begin
                            reduced_deg_reg <= phase2_reduced + 16'sd180;
                            result_sign_reg <= ~result_sign_reg; // 符号翻转
                        end else begin
                            reduced_deg_reg <= fast_abs16(phase2_reduced);
                            // 符号已经由result_sign_reg保存
                        end
                        
                        start_deg_to_rad <= 1;
                        state <= DEG_TO_RAD;
                    end
                end

                DEG_TO_RAD: begin
                    if (deg_to_rad_done) begin
                        if (deg_to_rad_error) begin
                            error  <= 1;
                            result <= 16'hFFC0;
                            done   <= 1;
                            state  <= IDLE;
                        end else begin
                            // 启动CORDIC，同时存储角度值到流水线寄存器
                            start_cordic <= 1;
                            state <= CORDIC;
                        end
                    end
                end

                CORDIC: begin
                    if (cordic_done) begin
                        if (fast_abs16(cos_q14) <= COS_MIN) begin
                            error  <= 1;
                            result <= 16'hFFC0;
                            state  <= OUTPUT;
                        end else begin
                            // 并行启动sin和cos的BF16转换
                            start_sin_bf16 <= 1;
                            start_cos_bf16 <= 1;
                            state <= CONV_SIN;
                        end
                    end
                end

                CONV_SIN: begin
                    // 等待sin转换完成，cos转换会并行进行
                    if (sin_bf16_done && cos_bf16_done) begin
                        start_bf16_div <= 1;
                        state <= BF16_DIV;
                    end
                end

                BF16_DIV: begin
                    if (bf16_div_done) begin
                        if (bf16_div_error) begin
                            error  <= 1;
                            result <= 16'hFFC0;
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