// Number format: Q2.14
// Verilog-2001
// Must run at 300MHz
// No IP cores or direct LUT implementations allowed

module cordic_core #(
    parameter MODE = 0,               // 0: SIN, 1: ARCTAN
    parameter integer ITERATIONS = 11,
    parameter DEEP_PIPELINE = 1       // 0: single-cycle/stage; 1: two-cycle/stage (split shift and add/sub)
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    // SIN: angle (rad, Q2.14); ARCTAN: x in Q2.14 (y is fixed to 1.0)
    input  wire signed [15:0] angle_q14,
    output reg  signed [15:0] result_q14,
    output reg  signed [15:0] secondary_q14,
    output reg  cordic_valid,
    output reg  done
);
    localparam signed [15:0] K_Q14      = 16'h26E2; // 0.607252935 * 2^14
    localparam signed [15:0] ONE_FIXED  = 16'h4000; // 1.0 in Q2.14

    // Angle lookup function (Q2.14, rad * 2^14)
    function automatic signed [15:0] angle_lut;
        input integer idx;
        begin
            case (idx)
                0:  angle_lut = 16'h3244; // atan(2^-0)
                1:  angle_lut = 16'h1DAE; // atan(2^-1)
                2:  angle_lut = 16'h0FAE; // atan(2^-2)
                3:  angle_lut = 16'h07F6; // atan(2^-3)
                4:  angle_lut = 16'h03FF; // atan(2^-4)
                5:  angle_lut = 16'h0200; // atan(2^-5)
                6:  angle_lut = 16'h0100; // atan(2^-6)
                7:  angle_lut = 16'h0080; // atan(2^-7)
                8:  angle_lut = 16'h0040; // atan(2^-8)
                9:  angle_lut = 16'h0020; // atan(2^-9)
                10: angle_lut = 16'h0010; // atan(2^-10)
                default: angle_lut = 16'sd0;
            endcase
        end
    endfunction

    // Data pipeline
    reg signed [15:0] x_pipe [0:ITERATIONS];
    reg signed [15:0] y_pipe [0:ITERATIONS];
    reg signed [15:0] z_pipe [0:ITERATIONS];

    // Valid signal pipeline
    reg valid_pipe [0:ITERATIONS];

    // Intermediate registers used only when DEEP_PIPELINE=1
    reg signed [15:0] x_shift   [0:ITERATIONS-1];
    reg signed [15:0] y_shift   [0:ITERATIONS-1];
    reg signed [15:0] lut_reg   [0:ITERATIONS-1];
    reg               valid_shift [0:ITERATIONS-1];

    // Stage 0: load input
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_pipe[0]     <= 16'sd0;
            y_pipe[0]     <= 16'sd0;
            z_pipe[0]     <= 16'sd0;
            valid_pipe[0] <= 1'b0;
        end else begin
            if (start) begin
                case (MODE)
                    0: begin // SIN
                        x_pipe[0] <= K_Q14;
                        y_pipe[0] <= 16'sd0;
                        z_pipe[0] <= angle_q14;
                    end
                    1: begin // ARCTAN
                        x_pipe[0] <= ONE_FIXED;
                        y_pipe[0] <= angle_q14;
                        z_pipe[0] <= 16'sd0;
                    end
                    default: begin
                        x_pipe[0] <= K_Q14;
                        y_pipe[0] <= 16'sd0;
                        z_pipe[0] <= angle_q14;
                    end
                endcase
                valid_pipe[0] <= 1'b1;
            end else begin
                valid_pipe[0] <= 1'b0;
            end
        end
    end

    // Iterative pipeline
    genvar i;
    generate
        for (i = 0; i < ITERATIONS; i = i + 1) begin : cordic_stage
            if (DEEP_PIPELINE) begin : deep
                // Phase A: shift and LUT register
                always @(posedge clk or posedge rst) begin
                    if (rst) begin
                        x_shift[i]     <= 16'sd0;
                        y_shift[i]     <= 16'sd0;
                        lut_reg[i]     <= 16'sd0;
                        valid_shift[i] <= 1'b0;
                    end else begin
                        x_shift[i]     <= x_pipe[i] >>> i;
                        y_shift[i]     <= y_pipe[i] >>> i;
                        lut_reg[i]     <= angle_lut(i);
                        valid_shift[i] <= valid_pipe[i];
                    end
                end

                // Phase B: add/sub and z update
                always @(posedge clk or posedge rst) begin
                    if (rst) begin
                        x_pipe[i+1]     <= 16'sd0;
                        y_pipe[i+1]     <= 16'sd0;
                        z_pipe[i+1]     <= 16'sd0;
                        valid_pipe[i+1] <= 1'b0;
                    end else begin
                        valid_pipe[i+1] <= valid_shift[i];
                        case (MODE)
                            0: begin // rotation mode
                                if (z_pipe[i][15]) begin
                                    x_pipe[i+1] <= x_pipe[i] + y_shift[i];
                                    y_pipe[i+1] <= y_pipe[i] - x_shift[i];
                                    z_pipe[i+1] <= z_pipe[i] + lut_reg[i];
                                end else begin
                                    x_pipe[i+1] <= x_pipe[i] - y_shift[i];
                                    y_pipe[i+1] <= y_pipe[i] + x_shift[i];
                                    z_pipe[i+1] <= z_pipe[i] - lut_reg[i];
                                end
                            end
                            1: begin // vectoring mode
                                if (y_pipe[i][15]) begin
                                    x_pipe[i+1] <= x_pipe[i] - y_shift[i];
                                    y_pipe[i+1] <= y_pipe[i] + x_shift[i];
                                    z_pipe[i+1] <= z_pipe[i] - lut_reg[i];
                                end else begin
                                    x_pipe[i+1] <= x_pipe[i] + y_shift[i];
                                    y_pipe[i+1] <= y_pipe[i] - x_shift[i];
                                    z_pipe[i+1] <= z_pipe[i] + lut_reg[i];
                                end
                            end
                            default: begin
                                x_pipe[i+1] <= 16'sd0;
                                y_pipe[i+1] <= 16'sd0;
                                z_pipe[i+1] <= 16'sd0;
                            end
                        endcase
                    end
                end
            end else begin : shallow
                // Original single-cycle/stage implementation
                always @(posedge clk or posedge rst) begin
                    if (rst) begin
                        x_pipe[i+1]     <= 16'sd0;
                        y_pipe[i+1]     <= 16'sd0;
                        z_pipe[i+1]     <= 16'sd0;
                        valid_pipe[i+1] <= 1'b0;
                    end else begin
                        valid_pipe[i+1] <= valid_pipe[i];
                        case (MODE)
                            0: begin // rotation mode
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
                            1: begin // vectoring mode
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
                                x_pipe[i+1] <= 16'sd0;
                                y_pipe[i+1] <= 16'sd0;
                                z_pipe[i+1] <= 16'sd0;
                            end
                        endcase
                    end
                end
            end
        end
    endgenerate

    // Output selection and done/valid pulse
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_q14    <= 16'sd0;
            secondary_q14 <= 16'sd0;
            cordic_valid  <= 1'b0;
            done          <= 1'b0;
        end else begin
            cordic_valid <= valid_pipe[ITERATIONS];
            done         <= valid_pipe[ITERATIONS]; // single-cycle pulse

            case (MODE)
                0: begin // SIN: result=sin, secondary=cos
                    result_q14    <= y_pipe[ITERATIONS];
                    secondary_q14 <= x_pipe[ITERATIONS];
                end
                1: begin // ARCTAN: result=angle, secondary=x_final
                    result_q14    <= z_pipe[ITERATIONS];
                    secondary_q14 <= x_pipe[ITERATIONS];
                end
                default: begin
                    result_q14    <= 16'sd0;
                    secondary_q14 <= 16'sd0;
                end
            endcase
        end
    end
endmodule