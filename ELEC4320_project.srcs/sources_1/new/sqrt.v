`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/12 16:05:57
// Design Name: 
// Module Name: sqrt
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


module sqrt(
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [`INPUTOUTBIT-1:0] a, //integer
    output reg signed [`INPUTOUTBIT-1:0] result, // 32 bit IEEE754
    output reg error = 0,
    output reg done
);

    reg [63:0] remainder;
    reg [63:0] root;
    reg [31:0] a_abs;
    reg [5:0] start_index;
    reg [5:0] fraction_count;
    reg[1:0] state;
    
    localparam S_IDLE=0,
               S_CALC_INT=1,
               S_CALC_FRACTION=2,
               S_OUTPUT=3;
               
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;
    integer leading;           
               
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 0;
            done   <= 0;
            state<=S_IDLE;
        end else begin
            case (state)
            
            S_IDLE: begin
                done<=0;
                if (start) begin
//                  Negative input
                    if (a[31]==1) begin
                        error<=1;
                        done<=1;
//                  Zero Case
                    end else if (a==0) begin
                        result<=32'h00000000;
                        done<=1;
                      
                    end else begin
                        a_abs<=a;
                        remainder<=0;
                        root<=0;
                        start_index<=16;
                        state<=S_CALC_INT;
                        fraction_count<=0;
                    end
                end
            end

            S_CALC_INT: begin
                remainder<=(remainder<<2)|((a_abs>>((start_index-1)*2))&2'b11);
                if((root<<1|1)<=remainder) begin
                        remainder<=remainder-(root<<1|1);
                        root<=(root<<1)|1;
                    end else begin
                        root<=(root<<1);
                    end
                    start_index<=start_index-1;
                    
                if (start_index==0) 
                    state<=S_CALC_FRACTION;
            end
            
            S_CALC_FRACTION: begin
                    remainder<=remainder<<2;
                    if((root<<1|1)<=remainder)begin
                        remainder<=remainder-(root<<1|1);
                        root<=(root<<1)|1;
                    end else begin
                        root<=root<<1;
                    end
                    fraction_count<=fraction_count+1;
                    if (fraction_count >= 24)
                        state<=S_OUTPUT;
                end
                
            // Convert to IEEE-754 float for output
            S_OUTPUT: begin
            // sqrt is always non-negative
                sign<=0; 
                leading=63;
                while (leading >= 0 && root[leading] == 0) 
                    leading=leading-1;
                if (leading<0) begin
                    exp<=0;
                    mant<=0;
                end else begin
                     exp=8'd127+(leading-24);
                    if (leading>23)
                        mant<=root>>(leading-23);
                    else
                        mant<=root<<(23-leading)&23'h7FFFFF; // mask 23 bits
                end
            
                result <= {sign, exp, mant};
                done <= 1;
                state <= S_IDLE;
            end
            endcase
        end
    end
endmodule
