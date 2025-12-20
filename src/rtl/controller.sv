module controller (
    input logic [6:0] opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    output logic reg_write,
    output logic [2:0] result_src,
    output logic is_store,
    output logic alu_src,
    output logic [3:0] alu_ctrl,
    output logic branch,
    output logic jump,
    output logic jalr
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
            default: ;
        endcase
    end
    
    // ALU Decoder
    always_comb begin
        case (alu_op)
            2'b00: alu_ctrl = 4'b0000; // add
            2'b01: begin // branches
                case (funct3)
                    3'b000, 3'b001: alu_ctrl = 4'b0001; // sub
                    3'b100, 3'b101: alu_ctrl = 4'b1000; // slt
                    3'b110, 3'b111: alu_ctrl = 4'b1001; // sltu
                    default: alu_ctrl = 4'b0000;
                endcase
            end
            2'b10: begin // R-type or I-type ALU
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5] && opcode[5]) ? 4'b0001 : 4'b0000; // sub / add
                    3'b001: alu_ctrl = 4'b0101; // sll
                    3'b010: alu_ctrl = 4'b1000; // slt
                    3'b011: alu_ctrl = 4'b1001; // sltu
                    3'b100: alu_ctrl = 4'b0100; // xor
                    3'b101: alu_ctrl = funct7[5] ? 4'b0111 : 4'b0110; // sra / srl
                    3'b110: alu_ctrl = 4'b0011; // or
                    3'b111: alu_ctrl = 4'b0010; // and
                    default: alu_ctrl = 4'b0000;
                endcase
            end
            default: alu_ctrl = 4'b0000;
        endcase
    end
endmodule
