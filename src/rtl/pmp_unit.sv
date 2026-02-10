module pmp_unit (
    input  logic [31:0] pmpcfg0,
    input  logic [31:0] pmpaddr [4],

    input  logic [1:0]  priv_mode,  // 2'b11 = M, 2'b00 = U

    // Instruction fetch check
    input  logic [31:0] pc,

    // Data access check
    input  logic [31:0] data_addr,
    input  logic        data_read,
    input  logic        data_write,

    output logic        pmp_instr_fault,
    output logic        pmp_load_fault,
    output logic        pmp_store_fault
);

    localparam [1:0] TOR   = 2'b01;
    localparam [1:0] NA4   = 2'b10;
    localparam [1:0] NAPOT = 2'b11;

    // Per-entry config fields
    logic [7:0] cfg [4];
    logic       L   [4];
    logic [1:0] A   [4];
    logic       X   [4];
    logic       W   [4];
    logic       R   [4];

    // Address match results
    logic instr_match [4];
    logic data_match  [4];

    // TOR lower bounds (entry 0 = 0, entry i = pmpaddr[i-1])
    logic [29:0] tor_lower [4];

    // NAPOT masks
    logic [29:0] napot_mask [4];

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : pmp_entry
            assign cfg[i] = pmpcfg0[i*8 +: 8];
            assign L[i]   = cfg[i][7];
            assign A[i]   = cfg[i][4:3];
            assign X[i]   = cfg[i][2];
            assign W[i]   = cfg[i][1];
            assign R[i]   = cfg[i][0];

            if (i == 0) begin : tor_base
                assign tor_lower[0] = 30'd0;
            end else begin : tor_prev
                assign tor_lower[i] = pmpaddr[i-1][29:0];
            end

            assign napot_mask[i] = ~(pmpaddr[i][29:0] ^ (pmpaddr[i][29:0] + 30'd1));
        end
    endgenerate

    // Address matching
    always_comb begin
        for (int j = 0; j < 4; j++) begin
            case (A[j])
                TOR: begin
                    instr_match[j] = (pc[31:2] >= tor_lower[j]) && (pc[31:2] < pmpaddr[j][29:0]);
                    data_match[j]  = (data_addr[31:2] >= tor_lower[j]) && (data_addr[31:2] < pmpaddr[j][29:0]);
                end
                NA4: begin
                    instr_match[j] = (pc[31:2] == pmpaddr[j][29:0]);
                    data_match[j]  = (data_addr[31:2] == pmpaddr[j][29:0]);
                end
                NAPOT: begin
                    instr_match[j] = ((pc[31:2] ^ pmpaddr[j][29:0]) & napot_mask[j]) == 30'd0;
                    data_match[j]  = ((data_addr[31:2] ^ pmpaddr[j][29:0]) & napot_mask[j]) == 30'd0;
                end
                default: begin // OFF
                    instr_match[j] = 1'b0;
                    data_match[j]  = 1'b0;
                end
            endcase
        end
    end

    // Any entry active? If no entries configured, U-mode is unrestricted (backward compat)
    logic any_active;
    assign any_active = (A[0] != 2'b00) | (A[1] != 2'b00) | (A[2] != 2'b00) | (A[3] != 2'b00);

    // Priority encoder: first matching entry wins
    logic       instr_found, data_found;
    logic       instr_r, instr_w, instr_x, instr_l;
    logic       data_r, data_w, data_x, data_l;

    always_comb begin
        instr_found = 1'b0;
        data_found  = 1'b0;
        instr_r = 1'b0; instr_w = 1'b0; instr_x = 1'b0; instr_l = 1'b0;
        data_r  = 1'b0; data_w  = 1'b0; data_x  = 1'b0; data_l  = 1'b0;

        for (int j = 0; j < 4; j++) begin
            if (!instr_found && instr_match[j]) begin
                instr_found = 1'b1;
                instr_r = R[j]; instr_w = W[j]; instr_x = X[j]; instr_l = L[j];
            end
            if (!data_found && data_match[j]) begin
                data_found = 1'b1;
                data_r = R[j]; data_w = W[j]; data_x = X[j]; data_l = L[j];
            end
        end
    end

    // Permission check
    always_comb begin
        // Instruction fetch
        if (instr_found) begin
            if (priv_mode == 2'b11)
                pmp_instr_fault = instr_l & ~instr_x;
            else
                pmp_instr_fault = ~instr_x;
        end else begin
            // No match: deny U-mode only if PMP is active
            pmp_instr_fault = (priv_mode == 2'b00) & any_active;
        end

        // Load
        if (data_found) begin
            if (priv_mode == 2'b11)
                pmp_load_fault = data_read & data_l & ~data_r;
            else
                pmp_load_fault = data_read & ~data_r;
        end else begin
            pmp_load_fault = data_read & (priv_mode == 2'b00) & any_active;
        end

        // Store
        if (data_found) begin
            if (priv_mode == 2'b11)
                pmp_store_fault = data_write & data_l & ~data_w;
            else
                pmp_store_fault = data_write & ~data_w;
        end else begin
            pmp_store_fault = data_write & (priv_mode == 2'b00) & any_active;
        end
    end

endmodule
