module alu (
    input logic [31:0] src_a,
    input logic [31:0] src_b,
    input logic [4:0] alu_ctrl,
    output logic [31:0] alu_result,
    output logic zero
);
    // 64-bit intermediates for multiply
    logic [63:0] mul_ss, mul_su, mul_uu;
    assign mul_ss = $signed({{32{src_a[31]}}, src_a}) * $signed({{32{src_b[31]}}, src_b});
    assign mul_uu = {32'b0, src_a} * {32'b0, src_b};
    assign mul_su = $signed({{32{src_a[31]}}, src_a}) * $signed({32'b0, src_b});

    always_comb begin
        case (alu_ctrl)
            // Base RV32I
            5'b00000: alu_result = src_a + src_b;                                        // ADD
            5'b00001: alu_result = src_a - src_b;                                        // SUB
            5'b00010: alu_result = src_a & src_b;                                        // AND
            5'b00011: alu_result = src_a | src_b;                                        // OR
            5'b00100: alu_result = src_a ^ src_b;                                        // XOR
            5'b00101: alu_result = src_a << src_b[4:0];                                  // SLL
            5'b00110: alu_result = src_a >> src_b[4:0];                                  // SRL
            5'b00111: alu_result = $signed(src_a) >>> src_b[4:0];                        // SRA
            5'b01000: alu_result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;   // SLT
            5'b01001: alu_result = (src_a < src_b) ? 32'd1 : 32'd0;                     // SLTU
            // RV32M
            5'b10000: alu_result = mul_ss[31:0];                                         // MUL
            5'b10001: alu_result = mul_ss[63:32];                                        // MULH
            5'b10010: alu_result = mul_su[63:32];                                        // MULHSU
            5'b10011: alu_result = mul_uu[63:32];                                        // MULHU
            5'b10100: alu_result = (src_b == 0) ? 32'hFFFFFFFF :                         // DIV
                                  (src_a == 32'h80000000 && src_b == 32'hFFFFFFFF) ? 32'h80000000 :
                                  $signed($signed(src_a) / $signed(src_b));
            5'b10101: alu_result = (src_b == 0) ? 32'hFFFFFFFF : src_a / src_b;          // DIVU
            5'b10110: alu_result = (src_b == 0) ? src_a :                                // REM
                                  (src_a == 32'h80000000 && src_b == 32'hFFFFFFFF) ? 32'b0 :
                                  $signed($signed(src_a) % $signed(src_b));
            5'b10111: alu_result = (src_b == 0) ? src_a : src_a % src_b;                 // REMU
            default: alu_result = 32'h0;
        endcase
        zero = (alu_result == 32'h0);
    end
endmodule
