// 数值格式为Q2.14
// arctan mode的时候，计算的结果是arctan(1/x)
// 需要运行在300MHz，可以调用DSP，但不可以用IP和直接用LUT

module cordic_core #(
    parameter MODE = 0,           // 0:SIN, 1:ARCTAN
    parameter integer ITERATIONS = 11
)(
    input wire clk,
    input wire rst,
    input wire start,
    // SIN: angle in rad Q2.14; ARCTAN: x in Q2.14 (y固定为1.0)
    input wire signed [15:0] angle_q14,
    output reg  signed [15:0] result_q14,
    output reg  signed [15:0] secondary_q14,
    output reg  cordic_valid,
    output reg  done
);
    localparam signed [15:0] K_Q14   = 16'h26E2; // 0.607252935 * 2^14
    localparam signed [15:0] ONE_FIXED = 16'h4000; // 1.0 in Q2.14

    // 根据迭代次数自动匹配流水深度
    reg signed [15:0] x_pipe [0:ITERATIONS];
    reg signed [15:0] y_pipe [0:ITERATIONS];
    reg signed [15:0] z_pipe [0:ITERATIONS];

    // 计数宽度自适应 ITERATIONS
    reg [$clog2(ITERATIONS+1)-1:0] iter_cnt;

    // Stage 0 init
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_pipe[0] <= 0; y_pipe[0] <= 0; z_pipe[0] <= 0;
        end else if (start) begin
            case (MODE)
                0: begin // SIN mode
                    x_pipe[0] <= K_Q14; 
                    y_pipe[0] <= 0; 
                    z_pipe[0] <= angle_q14; 
                end
                1: begin // ARCTAN mode: x=input, y=1.0
                    x_pipe[0] <= ONE_FIXED;
                    y_pipe[0] <= angle_q14;
                    z_pipe[0] <= 0; 
                end
                default: begin 
                    x_pipe[0] <= K_Q14; 
                    y_pipe[0] <= 0; 
                    z_pipe[0] <= angle_q14; 
                end
            endcase
        end
    end

    // Pipeline iterations
    genvar i;
    generate
        for (i = 0; i < ITERATIONS; i = i + 1) begin: cordic_stage
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    x_pipe[i+1] <= 0; y_pipe[i+1] <= 0; z_pipe[i+1] <= 0;
                end else begin
                    case (MODE)
                        0: begin // rotation mode for SIN
                            if (z_pipe[i][15]) begin
                                x_pipe[i+1] <= x_pipe[i] + (y_pipe[i] >>> i);
                                y_pipe[i+1] <= y_pipe[i] - (x_pipe[i] >>> i);
                                z_pipe[i+1] <= z_pipe[i] + angle_lut(i);
                            end else begin
                                x_pipe[i+1] <= x_pipe[i] - (y_pipe[i] >>> i);
                                y_pipe[i+1] <= y_pipe[i] + (x_pipe[i] >>> i);
                                z_pipe[i+1] <= z_pipe[i] - angle_lut(i);
                            end
                        end
                        1: begin // vectoring mode for ARCTAN
                            if (y_pipe[i][15]) begin
                                x_pipe[i+1] <= x_pipe[i] - (y_pipe[i] >>> i);
                                y_pipe[i+1] <= y_pipe[i] + (x_pipe[i] >>> i);
                                z_pipe[i+1] <= z_pipe[i] - angle_lut(i);
                            end else begin
                                x_pipe[i+1] <= x_pipe[i] + (y_pipe[i] >>> i);
                                y_pipe[i+1] <= y_pipe[i] - (x_pipe[i] >>> i);
                                z_pipe[i+1] <= z_pipe[i] + angle_lut(i);
                            end
                        end
                        default: begin
                            x_pipe[i+1] <= 0; y_pipe[i+1] <= 0; z_pipe[i+1] <= 0;
                        end
                    endcase
                end
            end
        end
    endgenerate

    // Output select
    reg signed [15:0] sin_val, cos_val;
    always @* begin
        sin_val = y_pipe[ITERATIONS];
        cos_val = x_pipe[ITERATIONS];
        case (MODE)
            0: begin // SIN: result = sin, secondary = cos
                result_q14     = sin_val;
                secondary_q14  = cos_val;
            end
            1: begin // ARCTAN: result = angle, secondary = x_final
                result_q14     = z_pipe[ITERATIONS];
                secondary_q14  = x_pipe[ITERATIONS];
            end
            default: begin
                result_q14     = 0;
                secondary_q14  = 0;
            end
        endcase
    end

    // Control (DONE脉冲1周期)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            iter_cnt     <= 0;
            cordic_valid <= 0;
            done         <= 0;
        end else begin
            cordic_valid <= 0;
            done         <= 0;
            if (start) begin
                iter_cnt <= 0;
            end else if (iter_cnt < ITERATIONS) begin
                iter_cnt <= iter_cnt + 1'b1;
                if (iter_cnt == ITERATIONS-1) begin
                    cordic_valid <= 1;
                    done         <= 1;
                end
            end
        end
    end

    // Angle lookup (Q2.14, rad*2^14)
    function [15:0] angle_lut;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  angle_lut = 16'h3244; // atan(2^-0)
                4'd1:  angle_lut = 16'h1DAE; // atan(2^-1)
                4'd2:  angle_lut = 16'h0FAE; // atan(2^-2)
                4'd3:  angle_lut = 16'h07F6; // atan(2^-3)
                4'd4:  angle_lut = 16'h03FF; // atan(2^-4)
                4'd5:  angle_lut = 16'h0200; // atan(2^-5)
                4'd6:  angle_lut = 16'h0100; // atan(2^-6)
                4'd7:  angle_lut = 16'h0080; // atan(2^-7)
                4'd8:  angle_lut = 16'h0040; // atan(2^-8)
                4'd9:  angle_lut = 16'h0020; // atan(2^-9)
                4'd10: angle_lut = 16'h0010; // atan(2^-10)
                default: angle_lut = 16'h0000;
            endcase
        end
    endfunction
endmodule