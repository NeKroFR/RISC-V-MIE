module controller (
    input logic [6:0] opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    input logic       funct12_0, // instr[20]
    output logic reg_write,
    output logic [2:0] result_src,
    output logic is_store,
    output logic alu_src,
    output logic [4:0] alu_ctrl,
    output logic branch,
    output logic jump,
    output logic jalr,
    output logic [3:0] trap_cause, // 0=None, 2=Illegal, 3=Break, 8=Ecall(U), 11=Ecall(M)
    output logic is_mret,
    output logic is_csr,
    input  logic [1:0] priv_mode   // 2'b11 = M, 2'b00 = U
);
    logic [1:0] alu_op;

    // Main Decoder
    always_comb begin
        reg_write = 0;
        result_src = 3'b000;
        is_store = 0;
        alu_src = 0;
        branch = 0;
        jump = 0;
        jalr = 0;
        alu_op = 2'b00;
        trap_cause = 4'd0;
        is_mret = 0;
        is_csr = 0;

        case (opcode)
            7'b0000011: begin // load
                reg_write = 1;
                alu_src = 1;
                result_src = 3'b001;
                alu_op = 2'b00;
            end
            7'b0100011: begin // store
                is_store = 1;
                alu_src = 1;
                alu_op = 2'b00;
            end
            7'b0110011: begin // R-type
                reg_write = 1;
                alu_op = 2'b10;
            end
            7'b0010011: begin // I-type ALU
                reg_write = 1;
                alu_src = 1;
                alu_op = 2'b10;
            end
            7'b1101111: begin // jal
                reg_write = 1;
                jump = 1;
                jalr = 0;
                result_src = 3'b010;
            end
            7'b1100111: begin // jalr
                reg_write = 1;
                alu_src = 1;
                jump = 1;
                jalr = 1;
                alu_op = 2'b00;
                result_src = 3'b010;
            end
            7'b1100011: begin // branch
                branch = 1;
                alu_op = 2'b01;
            end
            7'b0010111: begin // auipc
                reg_write = 1;
                result_src = 3'b011;
            end
            7'b0110111: begin // lui
                reg_write = 1;
                result_src = 3'b100;
            end
            7'b0001111: begin // FENCE
                // Treat as NOP for now
            end
            7'b1110011: begin // SYSTEM (ECALL, EBREAK, MRET, CSR)
                if (funct3 == 3'b000) begin
                    case (funct12_0) // Checks instr[20]
                        1'b0: begin
                            if (funct7 == 7'b0000000) begin
                                // ECALL: cause depends on privilege mode
                                trap_cause = (priv_mode == 2'b11) ? 4'd11 : 4'd8;
                            end else if (funct7 == 7'b0011000) begin
                                // MRET: only allowed in M-mode
                                if (priv_mode == 2'b11)
                                    is_mret = 1;
                                else
                                    trap_cause = 4'd2; // Illegal in U-mode
                            end
                        end
                        1'b1: begin
                            if (funct7 == 7'b0000000) trap_cause = 4'd3; // EBREAK
                        end
                    endcase
                end else begin
                    // CSR instructions: only allowed in M-mode
                    if (priv_mode == 2'b11) begin
                        reg_write = 1;
                        result_src = 3'b101;
                        is_csr = 1;
                    end else begin
                        trap_cause = 4'd2; // Illegal in U-mode
                    end
                end
            end
            default: begin
                // Illegal instruction
                trap_cause = 4'd2; 
            end
        endcase
    end
    
    // ALU Decoder
    always_comb begin
        case (alu_op)
            2'b00: alu_ctrl = 5'b00000; // add
            2'b01: begin // branches
                case (funct3)
                    3'b000, 3'b001: alu_ctrl = 5'b00001; // sub
                    3'b100, 3'b101: alu_ctrl = 5'b01000; // slt
                    3'b110, 3'b111: alu_ctrl = 5'b01001; // sltu
                    default: alu_ctrl = 5'b00000;
                endcase
            end
            2'b10: begin // R-type or I-type ALU
                if (funct7[0] && opcode[5]) begin
                    // M extension (R-type with funct7=0000001)
                    alu_ctrl = {2'b10, funct3}; // 10_xxx maps to MUL/DIV/REM
                end else begin
                    case (funct3)
                        3'b000: alu_ctrl = (funct7[5] && opcode[5]) ? 5'b00001 : 5'b00000; // sub / add
                        3'b001: alu_ctrl = 5'b00101; // sll
                        3'b010: alu_ctrl = 5'b01000; // slt
                        3'b011: alu_ctrl = 5'b01001; // sltu
                        3'b100: alu_ctrl = 5'b00100; // xor
                        3'b101: alu_ctrl = funct7[5] ? 5'b00111 : 5'b00110; // sra / srl
                        3'b110: alu_ctrl = 5'b00011; // or
                        3'b111: alu_ctrl = 5'b00010; // and
                        default: alu_ctrl = 5'b00000;
                    endcase
                end
            end
            default: alu_ctrl = 5'b00000;
        endcase
    end
endmodule
