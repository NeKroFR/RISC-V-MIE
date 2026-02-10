module csr_unit (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] pc_current,
    input  logic [3:0]  trap_cause,
    input  logic [31:0] trap_val,
    input  logic        is_mret,
    output logic        trap_taken,
    output logic [31:0] trap_pc,

    // CSR read/write interface
    input  logic        csr_write,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic [2:0]  csr_op,     // funct3
    output logic [31:0] csr_rdata,

    // Privilege mode
    output logic [1:0]  priv_mode,  // 2'b11 = M, 2'b00 = U

    // PMP outputs
    output logic [31:0] pmpcfg0_out,
    output logic [31:0] pmpaddr_out [4]
);

    // CSR Registers
    logic [31:0] mstatus;   // 0x300 — MIE[3], MPIE[7], MPP[12:11]
    logic [31:0] mtvec;     // 0x305
    logic [31:0] mscratch;  // 0x340
    logic [31:0] mepc;      // 0x341
    logic [31:0] mcause;    // 0x342
    logic [31:0] mtval;     // 0x343

    // PMP CSR Registers
    logic [31:0] pmpcfg0;   // 0x3A0 — 4 config bytes (entries 0-3)
    logic [31:0] pmpaddr [4]; // 0x3B0-0x3B3

    // PMP outputs
    assign pmpcfg0_out = pmpcfg0;
    assign pmpaddr_out = pmpaddr;

    localparam [31:0] MTVEC_RESET = 32'h00000100;

    // CSR Read (combinational)
    always_comb begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'h3A0: csr_rdata = pmpcfg0;
            12'h3B0: csr_rdata = pmpaddr[0];
            12'h3B1: csr_rdata = pmpaddr[1];
            12'h3B2: csr_rdata = pmpaddr[2];
            12'h3B3: csr_rdata = pmpaddr[3];
            default: csr_rdata = 32'b0;
        endcase
    end

    // Compute new CSR value based on operation
    logic [31:0] csr_new_val;
    always_comb begin
        case (csr_op[1:0])
            2'b01: csr_new_val = csr_wdata;              // CSRRW / CSRRWI
            2'b10: csr_new_val = csr_rdata | csr_wdata;  // CSRRS / CSRRSI
            2'b11: csr_new_val = csr_rdata & ~csr_wdata; // CSRRC / CSRRCI
            default: csr_new_val = csr_rdata;
        endcase
    end

    // Sequential: Trap entry/exit + CSR writes + privilege transitions
    always_ff @(posedge clk) begin
        if (reset) begin
            mstatus   <= 32'b0;
            mtvec     <= MTVEC_RESET;
            mscratch  <= 32'b0;
            mepc      <= 32'b0;
            mcause    <= 32'b0;
            mtval     <= 32'b0;
            pmpcfg0   <= 32'b0;
            pmpaddr[0] <= 32'b0;
            pmpaddr[1] <= 32'b0;
            pmpaddr[2] <= 32'b0;
            pmpaddr[3] <= 32'b0;
            priv_mode <= 2'b11; // Start in M-mode
        end else begin
            if (trap_cause != 0) begin
                // --- Trap Entry ---
                mepc   <= pc_current;
                mcause <= {28'b0, trap_cause};
                mtval  <= trap_val;
                // Save current privilege and interrupt state
                mstatus[12:11] <= priv_mode;      // MPP = current privilege
                mstatus[7]     <= mstatus[3];     // MPIE = MIE
                mstatus[3]     <= 1'b0;           // MIE = 0
                priv_mode      <= 2'b11;          // Enter M-mode
            end else if (is_mret) begin
                // --- MRET ---
                priv_mode      <= mstatus[12:11]; // Restore privilege from MPP
                mstatus[3]     <= mstatus[7];     // MIE = MPIE
                mstatus[7]     <= 1'b1;           // MPIE = 1
                mstatus[12:11] <= 2'b00;          // MPP = U-mode
            end else if (csr_write) begin
                // --- CSR Instruction Write ---
                case (csr_addr)
                    12'h300: mstatus  <= csr_new_val;
                    12'h305: mtvec    <= csr_new_val;
                    12'h340: mscratch <= csr_new_val;
                    12'h341: mepc     <= csr_new_val;
                    12'h342: mcause   <= csr_new_val;
                    12'h343: mtval    <= csr_new_val;
                    12'h3A0: begin
                        // pmpcfg0: skip writing bytes where L bit is set
                        if (!pmpcfg0[7])  pmpcfg0[7:0]   <= csr_new_val[7:0];
                        if (!pmpcfg0[15]) pmpcfg0[15:8]  <= csr_new_val[15:8];
                        if (!pmpcfg0[23]) pmpcfg0[23:16] <= csr_new_val[23:16];
                        if (!pmpcfg0[31]) pmpcfg0[31:24] <= csr_new_val[31:24];
                    end
                    12'h3B0: begin
                        // pmpaddr0: skip if entry 0 locked, or if entry 1 uses TOR and is locked
                        if (!pmpcfg0[7] && !(pmpcfg0[15] && pmpcfg0[12:11] == 2'b01))
                            pmpaddr[0] <= csr_new_val;
                    end
                    12'h3B1: begin
                        if (!pmpcfg0[15] && !(pmpcfg0[23] && pmpcfg0[20:19] == 2'b01))
                            pmpaddr[1] <= csr_new_val;
                    end
                    12'h3B2: begin
                        if (!pmpcfg0[23] && !(pmpcfg0[31] && pmpcfg0[28:27] == 2'b01))
                            pmpaddr[2] <= csr_new_val;
                    end
                    12'h3B3: begin
                        if (!pmpcfg0[31])
                            pmpaddr[3] <= csr_new_val;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Trap PC logic (combinational)
    always_comb begin
        trap_taken = (trap_cause != 0) || is_mret;

        if (is_mret) begin
            trap_pc = mepc;
        end else if (trap_cause != 0) begin
            trap_pc = mtvec;
        end else begin
            trap_pc = 32'b0;
        end
    end
endmodule
