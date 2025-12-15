`timescale 1ns / 1ps
`include "define.vh"

// ============================================================================
// Module: deg_to_rad - int deg -> Q2.14 rad
// ============================================================================
module deg_to_rad (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] angle_deg,  // 16-bit integer degrees [-999,999]
    output reg  signed [15:0] angle_q14,              // Q2.14 radians
    output reg  angle_valid,
    output reg  error,
    output reg  done
);
    localparam integer DEG_TO_RAD_Q14 = 286; 

    reg [2:0] state, next_state;
    localparam IDLE=3'd0, MUL1=3'd1, MUL2=3'd2, MUL3=3'd3, OUTPUT_ST=3'd4, DONE_ST=3'd5;

    reg signed [31:0] temp_mul;
    reg signed [31:0] temp_mul_reg;
    reg signed [15:0] deg_reg;
    reg signed [15:0] deg_reg2;

    // State register
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (start) next_state = MUL1;
            MUL1:      next_state = MUL2;
            MUL2:      next_state = MUL3;
            MUL3:      next_state = OUTPUT_ST;
            OUTPUT_ST: next_state = DONE_ST;
            DONE_ST:   next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end

    // Data path
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            angle_q14    <= 0;
            angle_valid  <= 0;
            error        <= 0;
            done         <= 0;
            temp_mul     <= 0;
            temp_mul_reg <= 0;
            deg_reg      <= 0;
            deg_reg2     <= 0;
        end else begin
            angle_valid <= 0;
            done        <= 0;

            case (state)
                IDLE: begin
                    if (start) begin
                        deg_reg <= angle_deg;
                        error   <= 0; // Clear error flag
                        deg_reg2 <= angle_deg; // Direct assignment, prepare for multiplication
                    end
                end

                MUL1: begin
                    temp_mul <= deg_reg2 * DEG_TO_RAD_Q14;
                end

                MUL2: begin
                    temp_mul_reg <= temp_mul;
                end

                MUL3: begin
                    // Delay only to ensure multiplication result stability
                end

                OUTPUT_ST: begin
                    angle_q14   <= temp_mul_reg[15:0];
                    angle_valid <= 1;
                end

                DONE_ST: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule

// ============================================================================
// Module: rad_to_deg - Q2.14 rad -> Q2.14 deg
// ============================================================================
module rad_to_deg (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [15:0] rad_q14,  // Input radians in Q2.14
    output reg signed [15:0] deg_q14,  // Output degrees in Q2.14
    output reg done
);
    // 180/pi ~= 57.2958 in Q2.14; Use 10-bit fractional scaling to avoid overflow
    localparam signed [31:0] RAD_TO_DEG_SCALE = 32'd58668;  // (180/pi) * 1024

    reg [2:0] state, next_state;
    localparam IDLE=3'd0, MUL1=3'd1, MUL2=3'd2, MUL3=3'd3, SHIFT=3'd4, OUTPUT_ST=3'd5;
    reg signed [31:0] temp;
    reg signed [31:0] temp_reg;
    reg signed [15:0] rad_reg;
    reg signed [15:0] rad_reg2;

    // State register
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (start) next_state = MUL1;
            MUL1:      next_state = MUL2;
            MUL2:      next_state = MUL3;
            MUL3:      next_state = SHIFT;
            SHIFT:     next_state = OUTPUT_ST;
            OUTPUT_ST: next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end

    // Data path
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            deg_q14  <= 0;
            done     <= 0;
            temp     <= 0;
            temp_reg <= 0;
            rad_reg  <= 0;
            rad_reg2 <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    if (start) rad_reg <= rad_q14;
                end

                MUL1: begin
                    rad_reg2 <= rad_reg;
                    temp     <= rad_reg * RAD_TO_DEG_SCALE;
                end

                MUL2: begin
                    temp_reg <= temp;
                end

                MUL3: begin
                    // Delay only to ensure multiplication result stability
                end

                SHIFT: begin
                    deg_q14 <= temp_reg[25:10];  // >>10 Keep 16 bits
                end

                OUTPUT_ST: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule

// ============================================================================
// Legacy module: angle_converter (for backward compatibility)
// ============================================================================
module angle_converter (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] angle_deg,  // 16-bit integer degrees [-999,999]
    output reg signed [15:0] angle_q14,  // Q2.14 format, [-pi/2, pi/2]
    output reg angle_valid,
    output reg error,
    output reg done
);
    deg_to_rad u_deg_to_rad (
        .clk(clk),
        .rst(rst),
        .start(start),
        .angle_deg(angle_deg),
        .angle_q14(angle_q14),
        .angle_valid(angle_valid),
        .error(error),
        .done(done)
    );
endmodule