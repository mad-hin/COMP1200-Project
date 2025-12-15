`timescale 1ns/1ps
// 协助计算tan(a)的除法器, a是整数角度
// 所以输出
// 最小值是 tan(1°) = 0.017455064
// 最大值是 tan(89°) = 57.28996163
// 本除法器的输入是 sin(a) 和 cos(a) 的 BF16 格式表示
// 输出是 tan(a) 的 BF16 格式表示
// Verilog-2001，CLK_PERIOD = 3

module bf16_divider (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [15:0] a,      // BF16: 1s, 8e, 7m
    input  wire [15:0] b,      // BF16: 1s, 8e, 7m
    output reg  [15:0] result, // BF16: 1s, 8e, 7m
    output reg         error,
    output reg         done
);

localparam IDLE  = 2'b00;
localparam CALC  = 2'b01;
localparam NORM  = 2'b10;
localparam DONE  = 2'b11;

reg [1:0] state, next_state;

// latch
reg [15:0] a_reg, b_reg;
reg        sign_reg;
reg [9:0]  exp_base_reg;      // (Ea - Eb + 127), allow small signed adjust in NORM
reg [31:0] q_reg;             // fixed-point ratio scaled by 2^F

// split (combinational, current inputs)
wire        a_sign = a[15];
wire [7:0]  a_exp  = a[14:7];
wire [6:0]  a_mant = a[6:0];

wire        b_sign = b[15];
wire [7:0]  b_exp  = b[14:7];
wire [6:0]  b_mant = b[6:0];

// specials (based on current inputs, as TB drives start with stable a/b)
wire a_zero = (a_exp == 8'h00) && (a_mant == 7'h00);
wire b_zero = (b_exp == 8'h00) && (b_mant == 7'h00);
wire a_inf  = (a_exp == 8'hFF) && (a_mant == 7'h00);
wire b_inf  = (b_exp == 8'hFF) && (b_mant == 7'h00);
wire a_nan  = (a_exp == 8'hFF) && (a_mant != 7'h00);
wire b_nan  = (b_exp == 8'hFF) && (b_mant != 7'h00);

wire result_sign = a_sign ^ b_sign;

// state transition
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (start) begin
                // handle specials in IDLE directly (same cycle decision)
                if (b_zero && !a_zero && !a_nan)
                    next_state = DONE;
                else if (a_nan || b_nan)
                    next_state = DONE;
                else if (a_inf && b_inf)
                    next_state = DONE;
                else if (a_inf)
                    next_state = DONE;
                else if (b_inf)
                    next_state = DONE;
                else if (a_zero && b_zero)
                    next_state = DONE;
                else if (a_zero && !b_zero)
                    next_state = DONE;
                else
                    next_state = CALC;
            end
        end
        CALC: next_state = NORM;
        NORM: next_state = DONE;
        DONE: next_state = IDLE;
        default: next_state = IDLE;
    endcase
end

// main sequential
localparam integer F = 16;        // fixed fractional bits for ratio
localparam integer UNDERFLOW_E = 100; // project/TB expected clamp-to-zero threshold

// For normalized BF16: significand = 1.mant7
// Represent significand as Q1.7 integer: S = 128 + mant7
wire [7:0] sa = {1'b1, a_reg[6:0]};
wire [7:0] sb = {1'b1, b_reg[6:0]};

integer exp_int;
reg [31:0] q_work;
reg [31:0] q_norm;
reg [6:0]  mant_out;
reg [7:0]  exp_out;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state        <= IDLE;
        a_reg        <= 16'h0;
        b_reg        <= 16'h0;
        sign_reg     <= 1'b0;
        exp_base_reg <= 10'd0;
        q_reg        <= 32'd0;
        result       <= 16'h0;
        error        <= 1'b0;
        done         <= 1'b0;
    end else begin
        state <= next_state;

        // default pulse behavior
        done  <= 1'b0;
        error <= 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    // latch inputs
                    a_reg    <= a;
                    b_reg    <= b;
                    sign_reg <= result_sign;

                    // base exponent (biased)
                    // exp_base = Ea - Eb + 127
                    exp_base_reg <= ({2'b00, a_exp} - {2'b00, b_exp} + 10'd127);

                    // specials output
                    if (b_zero && !a_zero && !a_nan) begin
                        result <= {result_sign, 8'hFF, 7'h00}; // Inf
                        error  <= 1'b1;
                        done   <= 1'b1;
                    end else if (a_nan || b_nan) begin
                        result <= 16'h7FC0; // NaN
                        error  <= 1'b1;
                        done   <= 1'b1;
                    end else if (a_inf && b_inf) begin
                        result <= 16'h7FC0; // NaN
                        error  <= 1'b1;
                        done   <= 1'b1;
                    end else if (a_inf) begin
                        result <= {result_sign, 8'hFF, 7'h00};
                        done   <= 1'b1;
                    end else if (b_inf) begin
                        result <= {result_sign, 8'h00, 7'h00}; // +0/-0
                        done   <= 1'b1;
                    end else if (a_zero && b_zero) begin
                        result <= 16'h7FC0; // NaN
                        error  <= 1'b1;
                        done   <= 1'b1;
                    end else if (a_zero && !b_zero) begin
                        // 0/finite => signed zero (TB checks sign too)
                        result <= {result_sign, 8'h00, 7'h00};
                        done   <= 1'b1;
                    end
                end
            end

            CALC: begin
                // Only handle normal finite here; subnormals are not generated by TB encoder (it truncates them to 0)
                // q = (Sa/Sb) * 2^F
                if (sb != 8'h00) begin
                    q_reg <= (({24'd0, sa} << F) / sb); // keep width safe
                end else begin
                    q_reg <= 32'd0;
                end
            end

            NORM: begin
                // Normalize ratio into [1,2) and adjust exponent accordingly
                // q_reg represents ratio * 2^F
                q_work = q_reg;
                exp_int = exp_base_reg;

                if (q_work == 0) begin
                    // treat as underflow/zero
                    result <= {sign_reg, 8'h00, 7'h00};
                    error  <= 1'b1;
                    done   <= 1'b1;
                end else begin
                    // If ratio >= 2.0 (rare), shift right and exp+1
                    if (q_work >= (32'd2 << F)) begin
                        q_norm = (q_work >> 1);
                        exp_int = exp_int + 1;
                    end
                    // If ratio in [1,2)
                    else if (q_work >= (32'd1 << F)) begin
                        q_norm = q_work;
                        // exp_int unchanged
                    end
                    // ratio in (0,1): shift left and exp-1
                    else begin
                        q_norm = (q_work << 1);
                        exp_int = exp_int - 1;
                    end

                    // Extract mantissa: mant7 = fractional top 7 bits after leading 1
                    // q_norm = (1.xxx) * 2^F  => leading 1 at bit F
                    // frac field is bits [F-1:0]
                    mant_out = (q_norm - (32'd1 << F)) >> (F - 7);

                    // Underflow clamp per project/TB expectation
                    if (exp_int <= UNDERFLOW_E) begin
                        result <= {sign_reg, 8'h00, 7'h00};
                        error  <= 1'b1;
                    end else if (exp_int >= 255) begin
                        result <= {sign_reg, 8'hFF, 7'h00};
                        error  <= 1'b1;
                    end else begin
                        exp_out = exp_int[7:0];
                        result  <= {sign_reg, exp_out, mant_out};
                    end

                    done <= 1'b1;
                end
            end

            DONE: begin
                // one-cycle DONE state, flags already pulsed in IDLE or NORM
            end
        endcase
    end
end

endmodule