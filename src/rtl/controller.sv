module controller (
    input logic [6:0] opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    input logic       funct12_0,   // instr[20]
    output logic reg_write,
    output logic [2:0] result_src,
    output logic is_store,
    output logic alu_src,
    output logic [4:0] alu_ctrl,
    output logic branch,
    output logic jump,
    output logic jalr,
    output logic [3:0] trap_cause, // 0=none, 2=illegal, 3=ebreak, 8/11=ecall
    output logic is_mret,
    output logic is_csr,
    output logic is_pac,
    input  logic [1:0] priv_mode   // 11=M, 00=U
);
    logic [1:0] alu_op;

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
        is_pac = 0;

        case (opcode)
            7'b0000011: begin // load
                reg_write = 1;
                alu_src = 1;
                result_src = 3'b001;
            end
            7'b0100011: begin // store
                is_store = 1;
                alu_src = 1;
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
                result_src = 3'b010;
            end
            7'b1100111: begin // jalr
                reg_write = 1;
                alu_src = 1;
                jump = 1;
                jalr = 1;
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
            7'b0001111: begin // fence (nop)
            end
            7'b1110011: begin // system (ecall, ebreak, mret, csr)
                if (funct3 == 3'b000) begin
                    case (funct12_0)
                        1'b0: begin
                            if (funct7 == 7'b0000000)
                                trap_cause = (priv_mode == 2'b11) ? 4'd11 : 4'd8; // ecall
                            else if (funct7 == 7'b0011000) begin
                                if (priv_mode == 2'b11)
                                    is_mret = 1;
                                else
                                    trap_cause = 4'd2; // mret illegal in U-mode
                            end
                        end
                        1'b1: begin
                            if (funct7 == 7'b0000000) trap_cause = 4'd3; // ebreak
                        end
                    endcase
                end else begin
                    if (priv_mode == 2'b11) begin
                        reg_write = 1;
                        result_src = 3'b101;
                        is_csr = 1;
                    end else begin
                        trap_cause = 4'd2; // CSRs are M-mode only
                    end
                end
            end
            7'b0001011: begin // custom-0: PAC
                is_pac = 1;
                if (funct7[0] == 1'b0) begin
                    // PACIA / PACDA: write the computed tag to rd
                    reg_write = 1;
                    result_src = 3'b110;
                end
                // AUTIA / AUTDA: no reg write, trap handled in riscv_cpu
            end
            default: begin
                trap_cause = 4'd2; // anything else is illegal
            end
        endcase
    end

    // ALU operation decode
    always_comb begin
        case (alu_op)
            2'b00: alu_ctrl = 5'b00000; // add (loads, stores, jalr)
            2'b01: begin // branches
                case (funct3)
                    3'b000, 3'b001: alu_ctrl = 5'b00001; // sub (beq/bne)
                    3'b100, 3'b101: alu_ctrl = 5'b01000; // slt (blt/bge)
                    3'b110, 3'b111: alu_ctrl = 5'b01001; // sltu (bltu/bgeu)
                    default: alu_ctrl = 5'b00000;
                endcase
            end
            2'b10: begin // R-type / I-type ALU
                if (funct7[0] && opcode[5]) begin
                    alu_ctrl = {2'b10, funct3}; // M-extension
                end else begin
                    case (funct3)
                        3'b000: alu_ctrl = (funct7[5] && opcode[5]) ? 5'b00001 : 5'b00000;
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
