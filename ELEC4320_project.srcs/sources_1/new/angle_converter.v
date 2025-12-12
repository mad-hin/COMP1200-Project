`timescale 1ns / 1ps

// ============================================================================
// Module: deg_to_rad - int deg -> Q2.14 rad, input range [-999,999]
// ============================================================================
module deg_to_rad (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [31:0] angle_deg,
    output reg  signed [15:0] angle_q14,
    output reg  angle_valid,
    output reg  error,
    output reg  done
);
    localparam integer DEG_TO_RAD_Q14 = 286; // (π/180)*2^14

    reg [1:0] state;
    localparam IDLE=2'd0, CALC=2'd1, DONE_ST=2'd2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            angle_q14   <= 0;
            angle_valid <= 0;
            error       <= 0;
            done        <= 0;
        end else begin
            angle_valid <= 0;
            done        <= 0;
            case (state)
                IDLE: begin
                    if (start) begin
                        if (angle_deg > 999 || angle_deg < -999) begin
                            error <= 1; done <= 1;
                        end else begin
                            error     <= 0;
                            angle_q14 <= angle_deg * DEG_TO_RAD_Q14; // Q2.14
                            state     <= CALC;
                        end
                    end
                end
                CALC: begin
                    angle_valid <= 1;
                    state       <= DONE_ST;
                end
                DONE_ST: begin
                    done  <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


// ============================================================================
// Module: rad_to_deg
// Description: Convert Q2.14 radians to Q2.14 degrees
// Input: Q2.14 radians [-π/2, π/2]
// Output: Q2.14 degrees
// ============================================================================
module rad_to_deg (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [15:0] rad_q14,  // Input radians in Q2.14
    
    output reg signed [15:0] deg_q14,  // Output degrees in Q2.14
    output reg done
);
    
    // Constants for conversion
    // 180/π ≈ 57.2958 in Q2.14: 57.2958 * 16384 ≈ 938,500
    // We'll use fixed-point scaling: 57.2958 * 2^10 ≈ 58668
    localparam signed [31:0] RAD_TO_DEG_SCALE = 32'd58668;  // (180/π) * 1024
    
    // Internal registers
    reg [1:0] state;
    localparam IDLE = 2'd0;
    localparam CALC = 2'd1;
    localparam OUTPUT = 2'd2;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            deg_q14 <= 0;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= CALC;
                    end
                end
                
                CALC: begin
                    // deg = rad * (180/π)
                    // Use 10-bit fractional scaling to avoid overflow
                    // deg_q14 = (rad_q14 * RAD_TO_DEG_SCALE) >> 10;
                    reg signed [31:0] temp;
                    temp = rad_q14 * RAD_TO_DEG_SCALE;
                    deg_q14 <= temp[25:10];  // Divide by 1024 (>>10) and keep 16 bits
                    state <= OUTPUT;
                end
                
                OUTPUT: begin
                    done <= 1;
                    state <= IDLE;
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
    input wire signed [31:0] angle_deg,  // -999 to 999
    
    output reg signed [15:0] angle_q14,  // Q2.14 format, [-π/2, π/2]
    output reg angle_valid,
    output reg error,
    output reg done
);
    
    // Instantiate deg_to_rad for backward compatibility
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