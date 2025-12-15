// arccos alu_acos (
//     .clk(clk),
//     .rst(rst),
//     .start(op_start && (sw_reg == `OP_ACOS)),
//     .a(a_val),
//     .result(acos_result),
//     .error(acos_error),
//     .done(acos_done)
// );

`timescale 1ns / 1ps
`include "define.vh"

module arccos (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,   // integer slope [-999,999]
    output reg  [`INPUTOUTBIT-1:0] result,     // BF16 angle in degrees
    output reg  error,
    output reg  done
);
    // States
    reg [1:0] state;
    localparam IDLE = 2'd0, DONE_ST = 2'd1;

    // Precomputed BF16 values
    localparam BF16_0    = 16'h0000;  // 0.0 in BF16
    localparam BF16_90   = 16'h42B4;  // 90.0 in BF16
    localparam BF16_180  = 16'h4334;  // 180.0 in BF16
    localparam BF16_NAN  = 16'hFFC0;  // NaN in BF16

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state  <= IDLE;
            result <= 0;
            error  <= 0;
            done   <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start) begin
                        if (a > 16'sd999 || a < -16'sd999) begin
                            error  <= 1;
                            result <= BF16_NAN;
                        end else if (a == -16'sd1) begin
                            result <= BF16_180;  // arccos(-1)=180
                            error  <= 0;
                        end else if (a == 16'sd0) begin
                            result <= BF16_90;   // arccos(0)=90
                            error  <= 0;
                        end else if (a == 16'sd1) begin
                            result <= BF16_0;    // arccos(1)=0
                            error  <= 0;
                        end else begin
                            error  <= 1;
                            result <= BF16_NAN;
                        end
                        done  <= 1;
                        state <= DONE_ST;
                    end
                end

                DONE_ST: begin
                    done <= 1;
                    if (!start) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule