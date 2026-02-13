module csr_unit (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] pc_current,
    input  logic [4:0]  trap_cause,
    input  logic [31:0] trap_val,
    input  logic        is_mret,
    output logic        trap_taken,
    output logic [31:0] trap_pc,

    input  logic        csr_write,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic [2:0]  csr_op,     // funct3
    output logic [31:0] csr_rdata,

    output logic [1:0]  priv_mode,  // 11=M, 00=U

    output logic [31:0] pmpcfg0_out,
    output logic [31:0] pmpaddr_out [4],

    output logic [127:0] pac_ia_key_out,
    output logic [127:0] pac_da_key_out,

    output logic [31:0] ktrr_base_out,
    output logic [31:0] ktrr_limit_out,
    output logic        ktrr_locked_out
);

    logic [31:0] mstatus;   // MIE[3], MPIE[7], MPP[12:11]
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;

    logic [31:0] pmpcfg0;
    logic [31:0] pmpaddr [4];

    // PAC keys: 128 bits each, split across 4 CSRs
    // k0 = {[1],[0]} (core key), w0 = {[3],[2]} (whitening key)
    logic [31:0] pac_ia_key [4]; // 0x7C0–0x7C3
    logic [31:0] pac_da_key [4]; // 0x7C4–0x7C7

    // KTRR (Kernel Text Read-Only Region)
    logic [31:0] ktrr_base;     // 0x7C8
    logic [31:0] ktrr_limit;    // 0x7C9
    logic        ktrr_locked;   // 0x7CA bit 0

    assign pmpcfg0_out = pmpcfg0;
    assign pmpaddr_out = pmpaddr;
    assign pac_ia_key_out = {pac_ia_key[3], pac_ia_key[2], pac_ia_key[1], pac_ia_key[0]};
    assign pac_da_key_out = {pac_da_key[3], pac_da_key[2], pac_da_key[1], pac_da_key[0]};
    assign ktrr_base_out  = ktrr_base;
    assign ktrr_limit_out = ktrr_limit;
    assign ktrr_locked_out = ktrr_locked;

    localparam [31:0] MTVEC_RESET = 32'h00000100;

    // CSR read
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
            12'h7C0: csr_rdata = pac_ia_key[0];
            12'h7C1: csr_rdata = pac_ia_key[1];
            12'h7C2: csr_rdata = pac_ia_key[2];
            12'h7C3: csr_rdata = pac_ia_key[3];
            12'h7C4: csr_rdata = pac_da_key[0];
            12'h7C5: csr_rdata = pac_da_key[1];
            12'h7C6: csr_rdata = pac_da_key[2];
            12'h7C7: csr_rdata = pac_da_key[3];
            12'h7C8: csr_rdata = ktrr_base;
            12'h7C9: csr_rdata = ktrr_limit;
            12'h7CA: csr_rdata = {31'b0, ktrr_locked};
            default: csr_rdata = 32'b0;
        endcase
    end

    // Read-modify-write logic for CSRRW/CSRRS/CSRRC
    logic [31:0] csr_new_val;
    always_comb begin
        case (csr_op[1:0])
            2'b01: csr_new_val = csr_wdata;              // CSRRW
            2'b10: csr_new_val = csr_rdata | csr_wdata;  // CSRRS
            2'b11: csr_new_val = csr_rdata & ~csr_wdata; // CSRRC
            default: csr_new_val = csr_rdata;
        endcase
    end

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
            pac_ia_key[0] <= 32'b0;
            pac_ia_key[1] <= 32'b0;
            pac_ia_key[2] <= 32'b0;
            pac_ia_key[3] <= 32'b0;
            pac_da_key[0] <= 32'b0;
            pac_da_key[1] <= 32'b0;
            pac_da_key[2] <= 32'b0;
            pac_da_key[3] <= 32'b0;
            ktrr_base   <= 32'b0;
            ktrr_limit  <= 32'b0;
            ktrr_locked <= 1'b0;
            priv_mode <= 2'b11;
        end else begin
            if (trap_cause != 5'd0) begin
                // Trap entry
                mepc   <= pc_current;
                mcause <= {27'b0, trap_cause};
                mtval  <= trap_val;
                mstatus[12:11] <= priv_mode;  // MPP
                mstatus[7]     <= mstatus[3]; // MPIE = MIE
                mstatus[3]     <= 1'b0;       // MIE = 0
                priv_mode      <= 2'b11;      // enter M-mode
            end else if (is_mret) begin
                priv_mode      <= mstatus[12:11]; // restore from MPP
                mstatus[3]     <= mstatus[7];     // MIE = MPIE
                mstatus[7]     <= 1'b1;
                mstatus[12:11] <= 2'b00;          // MPP = U
            end else if (csr_write) begin
                case (csr_addr)
                    12'h300: mstatus  <= csr_new_val;
                    12'h305: mtvec    <= csr_new_val;
                    12'h340: mscratch <= csr_new_val;
                    12'h341: mepc     <= csr_new_val;
                    12'h342: mcause   <= csr_new_val;
                    12'h343: mtval    <= csr_new_val;
                    12'h3A0: begin
                        // PMP config: locked bytes are read-only
                        if (!pmpcfg0[7])  pmpcfg0[7:0]   <= csr_new_val[7:0];
                        if (!pmpcfg0[15]) pmpcfg0[15:8]  <= csr_new_val[15:8];
                        if (!pmpcfg0[23]) pmpcfg0[23:16] <= csr_new_val[23:16];
                        if (!pmpcfg0[31]) pmpcfg0[31:24] <= csr_new_val[31:24];
                    end
                    12'h3B0: begin
                        // Also blocked if the next entry uses TOR and is locked
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
                    12'h7C0: pac_ia_key[0] <= csr_new_val;
                    12'h7C1: pac_ia_key[1] <= csr_new_val;
                    12'h7C2: pac_ia_key[2] <= csr_new_val;
                    12'h7C3: pac_ia_key[3] <= csr_new_val;
                    12'h7C4: pac_da_key[0] <= csr_new_val;
                    12'h7C5: pac_da_key[1] <= csr_new_val;
                    12'h7C6: pac_da_key[2] <= csr_new_val;
                    12'h7C7: pac_da_key[3] <= csr_new_val;
                    12'h7C8: if (!ktrr_locked) ktrr_base  <= csr_new_val;
                    12'h7C9: if (!ktrr_locked) ktrr_limit <= csr_new_val;
                    12'h7CA: if (!ktrr_locked) ktrr_locked <= csr_new_val[0];
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        trap_taken = (trap_cause != 5'd0) || is_mret;

        if (is_mret)
            trap_pc = mepc;
        else if (trap_cause != 5'd0)
            trap_pc = mtvec;
        else
            trap_pc = 32'b0;
    end
endmodule
