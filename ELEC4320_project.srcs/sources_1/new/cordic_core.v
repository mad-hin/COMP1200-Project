// 数值格式为Q2.14
`timescale 1ns / 1ps

module cordic_core #(
    parameter MODE = 0,  // 0:SIN, 1:COS, 2:TAN, 3:ARCTAN
    parameter integer ITERATIONS = 11
)(
    input wire clk,
    input wire rst,
    input wire start,
    // SIN/COS/TAN: angle in rad Q2.14; ARCTAN: y in Q2.14 (x=1)
    input wire signed [15:0] angle_q14,
    output reg  signed [15:0] result_q14,
    output reg  signed [15:0] secondary_q14,
    output reg  cordic_valid,
    output reg  done
);
    // // Angle table for 11 iterations in Q2.14 (rad*2^14)
    // localparam signed [15:0] angle_table [0:10] = '{
    //     16'h3244, // atan(2^-0)
    //     16'h1DAE, // atan(2^-1)
    //     16'h0FAE, // atan(2^-2)
    //     16'h07F6, // atan(2^-3)
    //     16'h03FF, // atan(2^-4)
    //     16'h0200, // atan(2^-5)
    //     16'h0100, // atan(2^-6)
    //     16'h0080, // atan(2^-7)
    //     16'h0040, // atan(2^-8)
    //     16'h0020, // atan(2^-9)
    //     16'h0010  // atan(2^-10)
    // };

    localparam signed [15:0] K_Q14    = 16'h26E2; // 0.607252935 * 2^14
    localparam signed [15:0] X_FIXED  = 16'h4000; // 1.0 in Q2.14

    reg signed [15:0] x_pipe [0:11];
    reg signed [15:0] y_pipe [0:11];
    reg signed [15:0] z_pipe [0:11];

    reg [3:0] state;
    reg [3:0] iteration;

    localparam IDLE = 4'd0, INIT = 4'd1, PIPE = 4'd2, OUTP = 4'd3;

    // Stage 0 init
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_pipe[0] <= 0; y_pipe[0] <= 0; z_pipe[0] <= 0;
        end else if (start) begin
            case (MODE)
                0,1,2: begin x_pipe[0] <= K_Q14; y_pipe[0] <= 0; z_pipe[0] <= angle_q14; end
                3:     begin x_pipe[0] <= X_FIXED; y_pipe[0] <= angle_q14; z_pipe[0] <= 0; end
                default: begin x_pipe[0] <= K_Q14; y_pipe[0] <= 0; z_pipe[0] <= angle_q14; end
            endcase
        end
    end

    // Pipeline iterations
    genvar i;
    generate
        for (i=0; i<11; i=i+1) begin: cordic_stage
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    x_pipe[i+1] <= 0; y_pipe[i+1] <= 0; z_pipe[i+1] <= 0;
                end else begin
                    case (MODE)
                        0,1,2: begin // rotation
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
                        3: begin // vectoring
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
    reg signed [31:0] tan_temp;

    always @* begin
        sin_val = y_pipe[11];
        cos_val = x_pipe[11];
        tan_temp = 0;
        case (MODE)
            0: begin result_q14 = sin_val; secondary_q14 = cos_val; end
            1: begin result_q14 = cos_val; secondary_q14 = sin_val; end
            2: begin
                if (cos_val != 0) begin
                    tan_temp = (sin_val * 16384) / cos_val;
                    if (tan_temp > 32767) result_q14 = 32767;
                    else if (tan_temp < -32768) result_q14 = -32768;
                    else result_q14 = tan_temp[15:0];
                end else result_q14 = (sin_val >= 0) ? 32767 : -32768;
                secondary_q14 = 0;
            end
            3: begin result_q14 = z_pipe[11]; secondary_q14 = x_pipe[11]; end
            default: begin result_q14 = 0; secondary_q14 = 0; end
        endcase
    end

    // Control FSM (latency = ITERATIONS cycles)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; cordic_valid <= 0; done <= 0; iteration <= 0;
        end else begin
            case (state)
                IDLE: begin cordic_valid <= 0; done <= 0; if (start) begin state <= INIT; iteration <= 0; end end
                INIT: begin if (iteration == ITERATIONS-1) begin state <= OUTP; iteration <= 0; end
                              else iteration <= iteration + 1'b1; end
                OUTP: begin cordic_valid <= 1; done <= 1; state <= IDLE; end
                default: state <= IDLE;
            endcase
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