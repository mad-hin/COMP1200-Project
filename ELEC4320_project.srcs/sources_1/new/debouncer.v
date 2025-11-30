`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.11.2025 18:31:52
// Design Name: 
// Module Name: debouncer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module debouncer #(
    parameter CNTW   = 20,
    parameter STABLE = 600000
)(
    input  wire clk,
    input  wire rst,
    input  wire din,
    output reg  dout
);
    reg sync0, sync1;
    always @(posedge clk) begin
        sync0 <= din;
        sync1 <= sync0;
    end

    // Stability counter
    reg [CNTW-1:0] cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dout <= 1'b0;
            cnt  <= {CNTW{1'b0}};
        end else if (sync1 == dout) begin
            // No change requested; reset counter
            cnt <= {CNTW{1'b0}};
        end else begin
            // Input differs from output; count how long it's stable
            cnt <= cnt + 1'b1;
            if (cnt >= STABLE[CNTW-1:0]) begin
                dout <= sync1; 
                cnt  <= {CNTW{1'b0}};
            end
        end
    end
endmodule
