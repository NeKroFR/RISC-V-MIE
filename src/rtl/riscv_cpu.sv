module riscv_cpu (
    input logic clk,
    input logic reset,
    output logic [31:0] pc,
    input logic [31:0] instr,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input logic [31:0] mem_rdata,
    output logic [3:0] mem_be
);
    // Internal Signals
    logic [31:0] pc_next, pc_plus4, pc_target;
    logic [31:0] rd1, rd2, imm_ext, src_b, alu_result;
    logic [3:0] alu_ctrl;
    logic reg_write, alu_src, zero, branch, jump, jalr, is_store;
    logic [2:0] result_src;
    logic taken;
    logic [31:0] result;
    logic [31:0] load_val;
    logic [31:0] store_data;

    // PC Logic
    assign pc_plus4 = pc + 4;
    assign pc_target = jalr ? (rd1 + imm_ext) : (pc + imm_ext);
    logic pc_src;
    assign pc_src = jump | taken;

    always_ff @(posedge clk) begin
        if (reset) pc <= 32'h0;
        else pc <= pc_next;
    end
    
    assign pc_next = pc_src ? pc_target : pc_plus4;
    
    // Immediate Extend
    always_comb begin
        case (instr[6:0])
            7'b0000011, 7'b0010011, 7'b1100111: // loads, I-ALU, jalr
                imm_ext = {{20{instr[31]}}, instr[31:20]};
            7'b0100011: // stores
                imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            7'b1100011: // branches
                imm_ext = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            7'b1101111: // jal
                imm_ext = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            7'b0010111, 7'b0110111: // auipc, lui
                imm_ext = {instr[31:12], 12'b0};
            default: imm_ext = 32'b0;
        endcase
    end
    
    // Controller
    controller ctrl (
        .opcode(instr[6:0]),
        .funct3(instr[14:12]),
        .funct7(instr[31:25]),
        .reg_write(reg_write),
        .result_src(result_src),
        .is_store(is_store),
        .alu_src(alu_src),
        .alu_ctrl(alu_ctrl),
        .branch(branch),
        .jump(jump),
        .jalr(jalr)
    );

    // Reg File
    reg_file register_file_inst (
        .clk(clk),
        .rs1(instr[19:15]),
        .rs2(instr[24:20]),
        .rd(instr[11:7]),
        .wd3(result),
        .we3(reg_write),
        .rd1(rd1),
        .rd2(rd2)
    );

    // ALU
    assign src_b = alu_src ? imm_ext : rd2;
    alu core_alu (
        .src_a(rd1),
        .src_b(src_b),
        .alu_ctrl(alu_ctrl),
        .alu_result(alu_result),
        .zero(zero)
    );


    assign mem_addr = alu_result;
    
    // Load extension
    always_comb begin
        logic [1:0] addr_lo = mem_addr[1:0];
        logic [7:0] bytev;
        logic [15:0] halfv;
        case(addr_lo)
            2'b00: bytev = mem_rdata[7:0];
            2'b01: bytev = mem_rdata[15:8];
            2'b10: bytev = mem_rdata[23:16];
            2'b11: bytev = mem_rdata[31:24];
        endcase
        case(addr_lo[1])
            1'b0: halfv = mem_rdata[15:0];
            1'b1: halfv = mem_rdata[31:16];
        endcase
        case(instr[14:12]) // funct3
            3'b000: load_val = {{24{bytev[7]}}, bytev}; // lb
            3'b001: load_val = {{16{halfv[15]}}, halfv}; // lh
            3'b010: load_val = mem_rdata; // lw
            3'b100: load_val = {24'b0, bytev}; // lbu
            3'b101: load_val = {16'b0, halfv}; // lhu
            default: load_val = 32'b0;
        endcase
    end

    // Store data alignment
    always_comb begin
        mem_be = 4'b0000;
        store_data = 32'b0;
        if(is_store) begin
            case(instr[14:12])
                3'b000: begin // sb
                    case(mem_addr[1:0])
                        2'b00: begin
                            mem_be = 4'b0001;
                            store_data[7:0] = rd2[7:0];
                        end
                        2'b01: begin
                            mem_be = 4'b0010;
                            store_data[15:8] = rd2[7:0];
                        end
                        2'b10: begin
                            mem_be = 4'b0100;
                            store_data[23:16] = rd2[7:0];
                        end
                        2'b11: begin
                            mem_be = 4'b1000;
                            store_data[31:24] = rd2[7:0];
                        end
                    endcase
                end
                3'b001: begin // sh
                    case(mem_addr[1:0])
                        2'b00: begin
                            mem_be = 4'b0011;
                            store_data[15:0] = rd2[15:0];
                        end
                        2'b10: begin
                            mem_be = 4'b1100;
                            store_data[31:16] = rd2[15:0];
                        end
                        default: ;
                    endcase
                end
                3'b010: begin // sw
                    mem_be = 4'b1111;
                    store_data = rd2;
                end
                default: ;
            endcase
        end
    end
    
    assign mem_wdata = store_data;

    // Branch taken
    always_comb begin
        case(instr[14:12])
            3'b000: taken = branch & zero;   // beq
            3'b001: taken = branch & ~zero;  // bne
            3'b100: taken = branch & ~zero;  // blt
            3'b101: taken = branch & zero;   // bge
            3'b110: taken = branch & ~zero;  // bltu
            3'b111: taken = branch & zero;   // bgeu
            default: taken = 0;
        endcase
    end
    
    // Result Mux
    always_comb begin
        case (result_src)
            3'b000: result = alu_result;
            3'b001: result = load_val;
            3'b010: result = pc_plus4;
            3'b011: result = pc + imm_ext;
            3'b100: result = imm_ext;
            default: result = 32'b0;
        endcase
    end
endmodule
