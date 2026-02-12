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
    logic [31:0] pc_next, pc_plus4, pc_target;
    logic [31:0] rd1, rd2, imm_ext, src_b, alu_result;
    logic [4:0] alu_ctrl;
    logic reg_write, alu_src, zero, branch, jump, jalr, is_store;
    logic [2:0] result_src;
    logic taken;
    logic [31:0] result;
    logic [31:0] load_val;
    logic [31:0] store_data;

    // Trap / CSR
    logic [3:0] trap_cause;
    logic [4:0] trap_cause_merged;  // widened to fit PAC cause 18
    logic [31:0] trap_val;
    logic is_mret;
    logic is_csr;
    logic trap_taken;
    logic [31:0] trap_pc;
    logic [31:0] csr_rdata;
    logic [31:0] csr_wdata;
    logic [1:0] priv_mode;

    // PMP
    logic [31:0] pmpcfg0;
    logic [31:0] pmpaddr [4];
    logic        pmp_instr_fault;
    logic        pmp_load_fault;
    logic        pmp_store_fault;
    logic        is_load;

    // PAC / QARMA
    logic        is_pac;
    logic        is_aut;
    logic        pac_is_da;
    logic        qarma_start, qarma_valid, qarma_busy;
    logic [63:0] qarma_result;
    logic [127:0] pac_ia_key, pac_da_key, pac_key_selected;
    logic [31:0] rd3;                  // reg[rd] readback for AUT comparison
    logic        pac_auth_fail;

    assign is_aut       = is_pac & instr[25];   // funct7[0]: 0=sign, 1=auth
    assign pac_is_da    = instr[12];            // funct3[0]: 0=IA key, 1=DA key
    assign pac_key_selected = pac_is_da ? pac_da_key : pac_ia_key;
    assign qarma_start  = is_pac & ~qarma_busy;
    assign pac_auth_fail = is_aut & qarma_valid & (qarma_result[31:0] != rd3);

    // Stall the whole pipeline while QARMA is running
    logic stall;
    assign stall = is_pac & ~qarma_valid;

    // PC
    assign pc_plus4 = pc + 4;
    assign pc_target = jalr ? ((rd1 + imm_ext) & ~32'b1) : (pc + imm_ext);

    logic pc_src;
    assign pc_src = jump | taken;

    always_ff @(posedge clk) begin
        if (reset) pc <= 32'h0;
        else if (!stall) pc <= pc_next;
    end

    // Trap overrides branch/jump
    assign pc_next = trap_taken ? trap_pc : (pc_src ? pc_target : pc_plus4);

    // Immediate decode
    always_comb begin
        case (instr[6:0])
            7'b0000011, 7'b0010011, 7'b1100111: // I-type (loads, ALU, jalr)
                imm_ext = {{20{instr[31]}}, instr[31:20]};
            7'b0100011: // S-type
                imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            7'b1100011: // B-type
                imm_ext = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            7'b1101111: // J-type
                imm_ext = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            7'b0010111, 7'b0110111: // U-type (auipc, lui)
                imm_ext = {instr[31:12], 12'b0};
            default: imm_ext = 32'b0;
        endcase
    end

    controller ctrl (
        .opcode(instr[6:0]),
        .funct3(instr[14:12]),
        .funct7(instr[31:25]),
        .funct12_0(instr[20]),
        .reg_write(reg_write),
        .result_src(result_src),
        .is_store(is_store),
        .alu_src(alu_src),
        .alu_ctrl(alu_ctrl),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .trap_cause(trap_cause),
        .is_mret(is_mret),
        .is_csr(is_csr),
        .is_pac(is_pac),
        .priv_mode(priv_mode)
    );

    assign is_load = (instr[6:0] == 7'b0000011);

    pmp_unit pmp (
        .pmpcfg0(pmpcfg0),
        .pmpaddr(pmpaddr),
        .priv_mode(priv_mode),
        .pc(pc),
        .data_addr(alu_result),
        .data_read(is_load),
        .data_write(is_store),
        .pmp_instr_fault(pmp_instr_fault),
        .pmp_load_fault(pmp_load_fault),
        .pmp_store_fault(pmp_store_fault)
    );

    // Fault merge: instr_fault > controller trap > PAC auth fail > load_fault > store_fault
    always_comb begin
        if (pmp_instr_fault)
            trap_cause_merged = 5'd1;
        else if (trap_cause != 0)
            trap_cause_merged = {1'b0, trap_cause};
        else if (pac_auth_fail)
            trap_cause_merged = 5'd18;
        else if (pmp_load_fault)
            trap_cause_merged = 5'd5;
        else if (pmp_store_fault)
            trap_cause_merged = 5'd7;
        else
            trap_cause_merged = 5'd0;
    end

    // mtval: faulting address for PMP/PAC, zero otherwise
    always_comb begin
        case (trap_cause_merged)
            5'd1:    trap_val = pc;
            5'd5:    trap_val = alu_result;
            5'd7:    trap_val = alu_result;
            5'd18:   trap_val = rd1;         // the pointer that failed auth
            default: trap_val = 32'd0;
        endcase
    end

    // CSR write data: register value for CSRRW/S/C, zero-extended zimm for I-variants
    assign csr_wdata = instr[14] ? {27'b0, instr[19:15]} : rd1;

    csr_unit csr (
        .clk(clk),
        .reset(reset),
        .pc_current(pc),
        .trap_cause(trap_cause_merged),
        .trap_val(trap_val),
        .is_mret(is_mret),
        .trap_taken(trap_taken),
        .trap_pc(trap_pc),
        .csr_write(is_csr & ~trap_taken & ~stall),
        .csr_addr(instr[31:20]),
        .csr_wdata(csr_wdata),
        .csr_op(instr[14:12]),
        .csr_rdata(csr_rdata),
        .priv_mode(priv_mode),
        .pmpcfg0_out(pmpcfg0),
        .pmpaddr_out(pmpaddr),
        .pac_ia_key_out(pac_ia_key),
        .pac_da_key_out(pac_da_key)
    );

    // Gate register writes during traps and stalls
    logic reg_write_gated;
    assign reg_write_gated = reg_write & ~trap_taken & ~stall;

    reg_file register_file_inst (
        .clk(clk),
        .rs1(instr[19:15]),
        .rs2(instr[24:20]),
        .rd(instr[11:7]),
        .wd3(result),
        .we3(reg_write_gated),
        .rd1(rd1),
        .rd2(rd2),
        .rd_addr2(instr[11:7]),      // 3rd port: reads reg[rd] for AUT
        .rd3(rd3)
    );

    qarma64 pac_engine (
        .clk(clk),
        .reset(reset),
        .start(qarma_start),
        .plaintext({32'b0, rd1}),
        .tweak({32'b0, rd2}),
        .key(pac_key_selected),
        .result(qarma_result),
        .valid(qarma_valid),
        .busy(qarma_busy)
    );

    assign src_b = alu_src ? imm_ext : rd2;
    alu core_alu (
        .src_a(rd1),
        .src_b(src_b),
        .alu_ctrl(alu_ctrl),
        .alu_result(alu_result),
        .zero(zero)
    );

    assign mem_addr = alu_result;

    // Sub-word load alignment
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
        case(instr[14:12])
            3'b000: load_val = {{24{bytev[7]}}, bytev}; // lb
            3'b001: load_val = {{16{halfv[15]}}, halfv}; // lh
            3'b010: load_val = mem_rdata;               // lw
            3'b100: load_val = {24'b0, bytev};          // lbu
            3'b101: load_val = {16'b0, halfv};          // lhu
            default: load_val = 32'b0;
        endcase
    end

    // Sub-word store alignment + byte enables
    always_comb begin
        mem_be = 4'b0000;
        store_data = 32'b0;
        if(is_store && !trap_taken && !stall) begin
            case(instr[14:12])
                3'b000: begin // sb
                    case(mem_addr[1:0])
                        2'b00: begin mem_be = 4'b0001; store_data[7:0]   = rd2[7:0]; end
                        2'b01: begin mem_be = 4'b0010; store_data[15:8]  = rd2[7:0]; end
                        2'b10: begin mem_be = 4'b0100; store_data[23:16] = rd2[7:0]; end
                        2'b11: begin mem_be = 4'b1000; store_data[31:24] = rd2[7:0]; end
                    endcase
                end
                3'b001: begin // sh
                    case(mem_addr[1:0])
                        2'b00: begin mem_be = 4'b0011; store_data[15:0]  = rd2[15:0]; end
                        2'b10: begin mem_be = 4'b1100; store_data[31:16] = rd2[15:0]; end
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

    // Branch resolution
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

    // Result mux
    always_comb begin
        case (result_src)
            3'b000: result = alu_result;
            3'b001: result = load_val;
            3'b010: result = pc_plus4;           // JAL/JALR link
            3'b011: result = pc + imm_ext;       // AUIPC
            3'b100: result = imm_ext;            // LUI
            3'b101: result = csr_rdata;
            3'b110: result = qarma_result[31:0]; // PAC
            default: result = 32'b0;
        endcase
    end
endmodule
