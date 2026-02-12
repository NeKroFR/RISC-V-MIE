// QARMA-64-5 block cipher for PAC (Pointer Authentication Code) generation.
// See docs/2016-444.pdf (Avanzi 2016) for the full spec.
//
// 14-cycle iterative engine, 1 round per clock:
//
//   Cycle  0     : whitening          IS = P ^ w0         (done at latch time)
//   Cycles 1–5   : forward rounds     AddTweakey -> Shuffle -> [Mix] -> SubCells
//   Cycle  6     : reflector part 1   AddTweakey(k0) -> SubCells -> MixColumns
//   Cycle  7     : reflector part 2   SubCells -> AddTweakey(k1)
//   Cycles 8–12  : backward rounds    SubCells -> [Mix] -> InvShuffle -> AddTweakey
//   Cycle  13    : final whitening    result = state ^ w1  (combinational)
//
// The reflector is split across two cycles so every cycle has roughly the
// same logic depth: one XOR layer + SubCells + MixColumns.

module qarma64 (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [63:0] plaintext,
    input  logic [63:0] tweak,
    input  logic [127:0] key,       // {w0, k0} = {key[127:64], key[63:0]}
    output logic [63:0] result,
    output logic        valid,
    output logic        busy
);

    // omega: LFSR-based key derivation (spec section 3.1)
    // Rotates right by 1 and XORs the wrapped bit into the MSB.
    function automatic [63:0] omega(input [63:0] x);
        omega = {x[0] ^ x[63], x[63:1]};
    endfunction

    // sigma_0: 4-bit S-box (involution, so encrypt = decrypt)
    function automatic [3:0] sbox(input [3:0] x);
        case (x)
            4'h0: sbox = 4'h0;  4'h1: sbox = 4'hE;
            4'h2: sbox = 4'h2;  4'h3: sbox = 4'hA;
            4'h4: sbox = 4'h9;  4'h5: sbox = 4'hF;
            4'h6: sbox = 4'h8;  4'h7: sbox = 4'hB;
            4'h8: sbox = 4'h6;  4'h9: sbox = 4'h4;
            4'hA: sbox = 4'h3;  4'hB: sbox = 4'h7;
            4'hC: sbox = 4'hD;  4'hD: sbox = 4'hC;
            4'hE: sbox = 4'h1;  4'hF: sbox = 4'h5;
        endcase
    endfunction

    // Apply S-box to all 16 nibbles in parallel
    function automatic [63:0] subcells(input [63:0] s);
        for (int i = 0; i < 16; i++)
            subcells[i*4 +: 4] = sbox(s[i*4 +: 4]);
    endfunction

    // ShuffleCells: nibble permutation tau (spec table 1)
    // tau = {0,11,6,13,10,1,12,7,5,14,3,8,15,4,9,2}
    // Nibble 0 is the MSB (bits [63:60]), nibble 15 is the LSB (bits [3:0]).
    function automatic [63:0] shuffle_cells(input [63:0] s);
        logic [3:0] n_in  [16];
        logic [3:0] n_out [16];
        for (int i = 0; i < 16; i++)
            n_in[i] = s[(15-i)*4 +: 4];
        n_out[0]  = n_in[0];   n_out[1]  = n_in[11];
        n_out[2]  = n_in[6];   n_out[3]  = n_in[13];
        n_out[4]  = n_in[10];  n_out[5]  = n_in[1];
        n_out[6]  = n_in[12];  n_out[7]  = n_in[7];
        n_out[8]  = n_in[5];   n_out[9]  = n_in[14];
        n_out[10] = n_in[3];   n_out[11] = n_in[8];
        n_out[12] = n_in[15];  n_out[13] = n_in[4];
        n_out[14] = n_in[9];   n_out[15] = n_in[2];
        for (int i = 0; i < 16; i++)
            shuffle_cells[(15-i)*4 +: 4] = n_out[i];
    endfunction

    // Inverse of ShuffleCells (tau^-1)
    function automatic [63:0] inv_shuffle_cells(input [63:0] s);
        logic [3:0] n_in  [16];
        logic [3:0] n_out [16];
        for (int i = 0; i < 16; i++)
            n_in[i] = s[(15-i)*4 +: 4];
        n_out[0]  = n_in[0];   n_out[1]  = n_in[5];
        n_out[2]  = n_in[15];  n_out[3]  = n_in[10];
        n_out[4]  = n_in[13];  n_out[5]  = n_in[8];
        n_out[6]  = n_in[2];   n_out[7]  = n_in[7];
        n_out[8]  = n_in[11];  n_out[9]  = n_in[14];
        n_out[10] = n_in[4];   n_out[11] = n_in[1];
        n_out[12] = n_in[6];   n_out[13] = n_in[3];
        n_out[14] = n_in[9];   n_out[15] = n_in[12];
        for (int i = 0; i < 16; i++)
            inv_shuffle_cells[(15-i)*4 +: 4] = n_out[i];
    endfunction

    // MixColumns (Midori-64 style, involutory)
    // State is a 4x4 nibble matrix in row-major order:
    //   n0  n1  n2  n3       Each column j is {n_j, n_{j+4}, n_{j+8}, n_{j+12}}.
    //   n4  n5  n6  n7       Each output nibble = XOR of the other three in its column.
    //   n8  n9  n10 n11
    //   n12 n13 n14 n15
    function automatic [63:0] mix_columns(input [63:0] s);
        logic [3:0] n [16];
        logic [3:0] m [16];
        for (int i = 0; i < 16; i++)
            n[i] = s[(15-i)*4 +: 4];
        for (int col = 0; col < 4; col++) begin
            m[col]    = n[col+4] ^ n[col+8] ^ n[col+12];
            m[col+4]  = n[col]   ^ n[col+8] ^ n[col+12];
            m[col+8]  = n[col]   ^ n[col+4] ^ n[col+12];
            m[col+12] = n[col]   ^ n[col+4] ^ n[col+8];
        end
        for (int i = 0; i < 16; i++)
            mix_columns[(15-i)*4 +: 4] = m[i];
    endfunction

    // Forward tweak permutation h (spec table 2)
    function automatic [63:0] update_tweak(input [63:0] t);
        logic [3:0] n_in  [16];
        logic [3:0] n_out [16];
        for (int i = 0; i < 16; i++)
            n_in[i] = t[(15-i)*4 +: 4];
        n_out[0]  = n_in[6];   n_out[1]  = n_in[5];
        n_out[2]  = n_in[14];  n_out[3]  = n_in[15];
        n_out[4]  = n_in[0];   n_out[5]  = n_in[1];
        n_out[6]  = n_in[2];   n_out[7]  = n_in[3];
        n_out[8]  = n_in[7];   n_out[9]  = n_in[12];
        n_out[10] = n_in[13];  n_out[11] = n_in[4];
        n_out[12] = n_in[8];   n_out[13] = n_in[9];
        n_out[14] = n_in[10];  n_out[15] = n_in[11];
        for (int i = 0; i < 16; i++)
            update_tweak[(15-i)*4 +: 4] = n_out[i];
    endfunction

    // Inverse tweak permutation h^-1 (for backward rounds)
    function automatic [63:0] inv_update_tweak(input [63:0] t);
        logic [3:0] n_in  [16];
        logic [3:0] n_out [16];
        for (int i = 0; i < 16; i++)
            n_in[i] = t[(15-i)*4 +: 4];
        n_out[0]  = n_in[4];   n_out[1]  = n_in[5];
        n_out[2]  = n_in[6];   n_out[3]  = n_in[7];
        n_out[4]  = n_in[11];  n_out[5]  = n_in[1];
        n_out[6]  = n_in[0];   n_out[7]  = n_in[8];
        n_out[8]  = n_in[12];  n_out[9]  = n_in[13];
        n_out[10] = n_in[14];  n_out[11] = n_in[15];
        n_out[12] = n_in[9];   n_out[13] = n_in[10];
        n_out[14] = n_in[2];   n_out[15] = n_in[3];
        for (int i = 0; i < 16; i++)
            inv_update_tweak[(15-i)*4 +: 4] = n_out[i];
    endfunction

    // Round constants c0–c5 (from digits of pi, spec section 3.2)
    localparam logic [63:0] RC0 = 64'h0000000000000000;
    localparam logic [63:0] RC1 = 64'h13198A2E03707344;
    localparam logic [63:0] RC2 = 64'hA4093822299F31D0;
    localparam logic [63:0] RC3 = 64'h082EFA98EC4E6C89;
    localparam logic [63:0] RC4 = 64'h452821E638D01377;
    localparam logic [63:0] RC5 = 64'hBE5466CF34E90C6C;

    logic [63:0] state_reg, tk_reg;
    logic [63:0] k0_reg, k1_reg, w1_reg;
    logic [3:0]  counter;
    logic        running;

    // Next-state logic
    logic [63:0] next_state, next_tk;
    logic [63:0] tmp, tmp_tk;
    logic [63:0] rc_sel;

    always_comb begin
        next_state = state_reg;
        next_tk = tk_reg;
        tmp = 64'b0;
        tmp_tk = 64'b0;
        rc_sel = 64'b0;

        case (counter)
            // Forward rounds 0–4
            4'd1, 4'd2, 4'd3, 4'd4, 4'd5: begin
                case (counter)
                    4'd1: rc_sel = RC0;
                    4'd2: rc_sel = RC1;
                    4'd3: rc_sel = RC2;
                    4'd4: rc_sel = RC3;
                    default: rc_sel = RC4;
                endcase
                tmp = state_reg ^ k0_reg ^ rc_sel ^ tk_reg;
                tmp = shuffle_cells(tmp);
                if (counter != 4'd1)       // MixColumns skipped in round 0
                    tmp = mix_columns(tmp);
                next_state = subcells(tmp);
                next_tk = update_tweak(tk_reg);
            end

            // Pseudo-reflector, part 1
            4'd6: begin
                tmp = state_reg ^ k0_reg ^ RC5 ^ tk_reg;
                tmp = subcells(tmp);
                next_state = mix_columns(tmp);
                next_tk = tk_reg;          // tweak stays put through the reflector
            end

            // Pseudo-reflector, part 2
            4'd7: begin
                tmp = subcells(state_reg);
                next_state = tmp ^ k1_reg ^ RC5 ^ tk_reg;
                next_tk = tk_reg;
            end

            // Backward rounds 4–0
            4'd8, 4'd9, 4'd10, 4'd11, 4'd12: begin
                case (counter)
                    4'd8:  rc_sel = RC4;
                    4'd9:  rc_sel = RC3;
                    4'd10: rc_sel = RC2;
                    4'd11: rc_sel = RC1;
                    default: rc_sel = RC0;
                endcase
                tmp_tk = inv_update_tweak(tk_reg);
                tmp = subcells(state_reg);
                if (counter != 4'd8)       // MixColumns skipped in backward round 4
                    tmp = mix_columns(tmp);
                tmp = inv_shuffle_cells(tmp);
                next_state = tmp ^ k1_reg ^ rc_sel ^ tmp_tk;
                next_tk = tmp_tk;
            end

            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state_reg <= 64'b0;
            tk_reg    <= 64'b0;
            k0_reg    <= 64'b0;
            k1_reg    <= 64'b0;
            w1_reg    <= 64'b0;
            counter   <= 4'd0;
            running   <= 1'b0;
        end else if (start && !running) begin
            // Latch inputs and do the initial whitening in the same cycle
            state_reg <= plaintext ^ key[127:64]; // P ^ w0
            tk_reg    <= tweak;
            k0_reg    <= key[63:0];
            k1_reg    <= omega(key[63:0]);
            w1_reg    <= omega(key[127:64]);
            counter   <= 4'd1;
            running   <= 1'b1;
        end else if (running) begin
            if (counter == 4'd13) begin
                running <= 1'b0;
                counter <= 4'd0;
            end else begin
                state_reg <= next_state;
                tk_reg    <= next_tk;
                counter   <= counter + 4'd1;
            end
        end
    end

    // Final whitening is purely combinational on the last cycle
    assign valid  = running & (counter == 4'd13);
    assign busy   = running;
    assign result = (running & (counter == 4'd13)) ? (state_reg ^ w1_reg) : 64'b0;

endmodule
