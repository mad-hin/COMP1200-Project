// fac alu_fac (
//     .clk(clk),
//     .rst(rst),
//     .start(op_start && (sw_reg == `OP_FAC)),
//     .a(a_val),
//     .result(fac_result),
//     .error(fac_error),
//     .done(fac_done)
// );

// 要求：
// 输入：a是整数，范围[-999,999]，不用检查
// 输出：a的阶乘，要用BF16的格式表示
// 当a < 0时，输出error=1，不用计算
// 当a = 0时，输出result=1(直接用BF16表示)
// 当a = 1时，输出result=1(直接用BF16表示)
// 当a > 12时，输出error=1，不用计算
// 内部计算用无符号32位整数计算，然后才转换成BF16格式最后输出
// 不可以用LUT和IP
// 需要运行在300Mhz的情况
// module里用英文注释

`timescale 1ns / 1ps
`include "define.vh"

module fac(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire signed [`INPUTOUTBIT-1:0] a,      // Integer input [-999, 999] (per req: no need to check range)
    output reg  signed [`INPUTOUTBIT-1:0] result, // BF16 output (16-bit)
    output reg  error,
    output reg  done
);

    // ============================================================
    // State definition
    // ============================================================
    reg [2:0] state;
    localparam IDLE      = 3'd0;
    localparam CHECK     = 3'd1;
    localparam MUL       = 3'd2; // pipeline stage 1: multiply
    localparam UPDATE    = 3'd3; // pipeline stage 2: commit multiply + counter++
    localparam CONVERT0  = 3'd4; // latch factorial value
    localparam CONVERT1  = 3'd5; // BF16 convert
    localparam DONE_ST   = 3'd6;

    // ============================================================
    // Internal registers
    // ============================================================
    reg signed [15:0] a_reg;     // latched input
    reg [31:0] fact_val;         // 32-bit unsigned factorial value
    reg [4:0]  counter;          // current multiplier
    reg [4:0]  target;           // n (2..12)

    reg [36:0] mult_full;        // holds fact_val * counter (width = 32+5)
    reg [31:0] fact_val_conv;    // latched value for BF16 conversion (timing relief)

    // BF16 constants
    localparam [15:0] BF16_ZERO   = 16'h0000; // +0.0
    localparam [15:0] BF16_ONE    = 16'h3F80; // 1.0 in BF16
    localparam [15:0] BF16_NAN    = 16'hFFC0; // NaN in BF16
    localparam [15:0] BF16_INF    = 16'h7F80; // Positive infinity

    // ============================================================
    // Leading-zero count (val != 0 expected when used)
    // ============================================================
    function automatic [4:0] clz32;
        input [31:0] val;
        integer i;
        begin : clz32_loop
            clz32 = 32;
            for (i = 31; i >= 0; i = i - 1) begin
                if (val[i]) begin
                    clz32 = 31 - i;
                    disable clz32_loop;
                end
            end
        end
    endfunction

    // ============================================================
    // Unsigned int32 -> BF16 (round-to-nearest-even)
    // ============================================================
    function automatic [15:0] int_to_bf16_rne;
        input [31:0] int_val;
        reg [7:0]  exp;
        reg [6:0]  mant;
        reg [4:0]  lz;
        reg [31:0] norm;
        reg        round_bit;
        reg        sticky;
        reg [7:0]  mant_ext; // 1 extra bit for carry
        begin
            if (int_val == 0) begin
                int_to_bf16_rne = BF16_ZERO;
            end else begin
                lz  = clz32(int_val);
                exp = 8'd127 + (8'd31 - {3'b0, lz});
                norm = int_val << lz;

                mant       = norm[30:24];
                round_bit  = norm[23];
                sticky     = |norm[22:0];

                mant_ext = {1'b0, mant};
                if (round_bit && (sticky || mant[0])) begin
                    mant_ext = mant_ext + 8'd1;
                end

                if (mant_ext[7]) begin
                    exp  = exp + 8'd1;
                    mant = 7'd0;
                end else begin
                    mant = mant_ext[6:0];
                end

                if (exp >= 8'hFF) begin
                    int_to_bf16_rne = BF16_INF;
                end else begin
                    int_to_bf16_rne = {1'b0, exp, mant};
                end
            end
        end
    endfunction

    // ============================================================
    // Main FSM
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            result       <= 0;
            error        <= 0;
            done         <= 0;
            a_reg        <= 0;
            fact_val     <= 0;
            counter      <= 0;
            target       <= 0;
            mult_full    <= 0;
            fact_val_conv<= 0;
        end else begin
            case (state)
                IDLE: begin
                    done  <= 0;
                    error <= 0;
                    if (start) begin
                        a_reg <= a;
                        state <= CHECK;
                    end
                end

                CHECK: begin
                    if (a_reg < 0) begin
                        error  <= 1;
                        result <= BF16_NAN;
                        state  <= DONE_ST;
                    end else if (a_reg == 0 || a_reg == 1) begin
                        result <= BF16_ONE;
                        state  <= DONE_ST;
                    end else if (a_reg > 12) begin
                        error  <= 1;
                        result <= BF16_NAN;
                        state  <= DONE_ST;
                    end else begin
                        target   <= a_reg[4:0];
                        fact_val <= 32'd1;
                        counter  <= 5'd2;
                        state    <= MUL;
                    end
                end

                MUL: begin
                    mult_full <= fact_val * counter;
                    state     <= UPDATE;
                end

                UPDATE: begin
                    fact_val <= mult_full[31:0];
                    if (counter == target) begin
                        state <= CONVERT0;
                    end else begin
                        counter <= counter + 5'd1;
                        state   <= MUL;
                    end
                end

                CONVERT0: begin
                    fact_val_conv <= fact_val;
                    state         <= CONVERT1;
                end

                CONVERT1: begin
                    result <= int_to_bf16_rne(fact_val_conv);
                    state  <= DONE_ST;
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