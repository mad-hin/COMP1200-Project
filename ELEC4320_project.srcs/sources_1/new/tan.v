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

//先将输入的角度等价到[-pi/2,pi/2]的范围，确保tan值和变换之前一致
//然后考虑如果输入是90度或-90度时，输出error
//CORDIC模式选择为0，然后同时获取sin和cos，Q2.14格式
//然后分别把sin和cos换算成BF16，然后才进行除法得到tan
//最后tan的结果要保持BF16格式

//不可以用LUT和IP
//需要运行在300Mhz的情况
//module里用英文注释

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
    reg deg_to_rad_kick;  // one-cycle start gate

    // Reduced angle register (in [-90,90])
    reg signed [15:0] reduced_deg_reg;

    // Pipeline registers
    reg signed [15:0] angle_q14_reg;
    reg signed [15:0] sin_q14_reg, cos_q14_reg;
    reg [15:0] sin_bf16_reg, cos_bf16_reg;

    // BF16 conversion ready flags
    reg sin_bf16_ready, cos_bf16_ready;

    // FSM states
    reg [3:0] state;
    localparam IDLE        = 4'd0;
    localparam REDUCE      = 4'd1;
    localparam CHECK_90    = 4'd2;
    localparam DEG_TO_RAD  = 4'd3;
    localparam CORDIC      = 4'd4;
    localparam CONV_START  = 4'd5;
    localparam CONV_SIN    = 4'd6;
    localparam BF16_DIV    = 4'd7;
    localparam OUTPUT      = 4'd8;

    // ============================================================================
    // Angle reduction function: map any degree to [-90, 90] (synthesizable)
    // ============================================================================
    function automatic signed [15:0] reduce_to_90;
        input signed [15:0] deg;
        reg signed [15:0] t;
        begin
            // Mod 180 to [0,180)
            t = deg + 16'sd3600; // add multiple of 180 to ensure positive
            t = t % 16'sd180;
            if (t < 0) t = t + 16'sd180;
            // Map to [-90,90]
            if (t > 16'sd90)
                reduce_to_90 = t - 16'sd180;
            else
                reduce_to_90 = t;
        end
    endfunction

    // ============================================================================
    // Submodules
    // ============================================================================

    // Degree to rad (Q2.14)
    deg_to_rad u_deg_to_rad (
        .clk(clk),
        .rst(rst),
        .start(start_deg_to_rad),
        .angle_deg(reduced_deg_reg),
        .angle_q14(angle_q14),
        .angle_valid(),          // unused
        .error(deg_to_rad_error),
        .done(deg_to_rad_done)
    );

    // CORDIC core: mode 0, outputs sin/cos in Q2.14
    cordic_core #(.MODE(0)) u_cordic (
        .clk(clk),
        .rst(rst),
        .start(start_cordic),
        .angle_q14(angle_q14_reg),
        .result_q14(sin_q14),     // sin
        .secondary_q14(cos_q14),  // cos
        .cordic_valid(),          // unused
        .done(cordic_done)
    );

    // Q2.14 to BF16: sin
    Q14_to_BF16 u_sin_bf16 (
        .clk(clk),
        .rst(rst),
        .start(start_sin_bf16),
        .q14_value(sin_q14_reg),
        .float_result(sin_bf16),
        .convert_valid(),        // unused
        .done(sin_bf16_done)
    );

    // Q2.14 to BF16: cos
    Q14_to_BF16 u_cos_bf16 (
        .clk(clk),
        .rst(rst),
        .start(start_cos_bf16),
        .q14_value(cos_q14_reg),
        .float_result(cos_bf16),
        .convert_valid(),        // unused
        .done(cos_bf16_done)
    );

    // BF16 divider: tan = sin / cos
    bf16_divider u_bf16_div (
        .clk(clk),
        .rst(rst),
        .start(start_bf16_div),
        .a(sin_bf16_reg),        // numerator: sin
        .b(cos_bf16_reg),        // denominator: cos
        .result(tan_bf16),
        .error(bf16_div_error),
        .done(bf16_div_done)
    );

    // ============================================================================
    // Main FSM
    // ============================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= IDLE;
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_sin_bf16   <= 0;
            start_cos_bf16   <= 0;
            start_bf16_div   <= 0;
            deg_to_rad_kick  <= 0;
            result           <= 0;
            error            <= 0;
            done             <= 0;
            reduced_deg_reg  <= 0;
            angle_q14_reg    <= 0;
            sin_q14_reg      <= 0;
            cos_q14_reg      <= 0;
            sin_bf16_reg     <= 0;
            cos_bf16_reg     <= 0;
            sin_bf16_ready   <= 0;
            cos_bf16_ready   <= 0;
        end else begin
            // default deassertions (one-cycle pulses)
            start_deg_to_rad <= 0;
            start_cordic     <= 0;
            start_sin_bf16   <= 0;
            start_cos_bf16   <= 0;
            start_bf16_div   <= 0;
            done             <= 0;

            // pipeline latching
            if (deg_to_rad_done) begin
                angle_q14_reg <= angle_q14;
            end
            if (cordic_done) begin
                sin_q14_reg <= sin_q14;
                cos_q14_reg <= cos_q14;
            end
            if (sin_bf16_done) begin
                sin_bf16_reg   <= sin_bf16;
                sin_bf16_ready <= 1;
            end
            if (cos_bf16_done) begin
                cos_bf16_reg   <= cos_bf16;
                cos_bf16_ready <= 1;
            end

            case (state)
                IDLE: begin
                    error           <= 0;
                    deg_to_rad_kick <= 0;
                    sin_bf16_ready  <= 0;
                    cos_bf16_ready  <= 0;
                    result          <= 0;
                    if (start) state <= REDUCE;
                end

                REDUCE: begin
                    reduced_deg_reg <= reduce_to_90(a);
                    state <= CHECK_90;
                end

                CHECK_90: begin
                    if (reduced_deg_reg == 16'sd90 || reduced_deg_reg == -16'sd90) begin
                        error  <= 1;
                        result <= 16'hFFC0; // BF16 NaN
                        done   <= 1;
                        state  <= IDLE;
                    end else begin
                        deg_to_rad_kick <= 1'b1;
                        state <= DEG_TO_RAD;
                    end
                end

                DEG_TO_RAD: begin
                    if (deg_to_rad_kick) begin
                        start_deg_to_rad <= 1;
                        deg_to_rad_kick  <= 0;
                    end
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
                        state <= CONV_START;
                    end
                end

                // Start BF16 conversions one cycle after cordic outputs are latched
                CONV_START: begin
                    sin_bf16_ready <= 0;
                    cos_bf16_ready <= 0;
                    start_sin_bf16 <= 1;
                    start_cos_bf16 <= 1;
                    state <= CONV_SIN;
                end

                CONV_SIN: begin
                    if (sin_bf16_ready && cos_bf16_ready) begin
                        sin_bf16_ready <= 0;
                        cos_bf16_ready <= 0;
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