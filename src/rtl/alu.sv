module alu (
    input logic [31:0] src_a,
    input logic [31:0] src_b,
    input logic [3:0] alu_ctrl,
    output logic [31:0] alu_result,
    output logic zero
);
    always_comb begin
        case (alu_ctrl)
            4'b0000: alu_result = src_a + src_b;                                        // 0x00: ADD
            4'b0001: alu_result = src_a - src_b;                                        // 0x01: SUB
            4'b0010: alu_result = src_a & src_b;                                        // 0x02: AND
            4'b0011: alu_result = src_a | src_b;                                        // 0x03: OR
            4'b0100: alu_result = src_a ^ src_b;                                        // 0x04: XOR
            4'b0101: alu_result = src_a << src_b[4:0];                                  // 0x05: SLL
            4'b0110: alu_result = src_a >> src_b[4:0];                                  // 0x06: SRL
            4'b0111: alu_result = $signed(src_a) >>> src_b[4:0];                        // 0x07: SRA
            4'b1000: alu_result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;    // 0x08: SLT
            4'b1001: alu_result = (src_a < src_b) ? 32'd1 : 32'd0;                      // 0x09: SLTU
            default: alu_result = 32'h0;
        endcase
        zero = (alu_result == 32'h0);
    end
endmodule
