# Architecture

## Overview

RV32IM CPU with Zicsr extension and M/U privilege modes.
Stall-capable datapath (multi-cycle operations supported via stall signal).
Harvard architecture — separate instruction and data memory.
Simulated via Verilator with DPI-C for UART I/O.

## ISA Support

| Extension | Instructions |
|-----------|-------------|
| RV32I | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU + immediate variants, LB/H/W/BU/HU, SB/H/W, BEQ/NE/LT/GE/LTU/GEU, JAL, JALR, LUI, AUIPC, ECALL, EBREAK, FENCE (NOP), MRET |
| RV32M | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| Zicsr | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| Custom-0 (PAC) | PACIA, PACDA, AUTIA, AUTDA |

## Datapath

```
                            +------------------------------------------------+
                            |                    riscv_cpu                   |
                            |                                                |
  +----------+   instr      |  +----------+  imm   +--------+                |
  |   IMEM   |──────────────┤  | Imm Ext  |───────>|        |                |
  |  64 KiB  |──────────┐  |  +----------+         |  ALU   |  alu_result    |
  +----------+          │  |                       | RV32IM |───────────┐    |
       ^                │  |  +------------+ ctrl  |        |           │    |
       |   pc           │  |  |            |──────>|        |           │    |
       |           instr│  |  | Controller |       +--------+           │    |
  +----------+          │  |  |            |is_pac    | |               │    |
  | PC Mux   |         └──┤   +------------+   rd1,rd2| |alu_result     │    |
  | tr/br/+4 |            |    |  ^  |    |        ^  | |               │    |
  +----------+            |    |  |  |trap |       |  | v               │    |
       ^                  |    |  |  |    v        |  | +----------+    │    |
       |   trap_pc        |    |  |  | +-------+   |  | |   PMP    |<───┘    |
       |                  |    |  |  └>| Fault |   |  | | 4 entries |        |
  +----------+ priv_mode  |    |  |    | Merge |   |  | +----------+         |
  | CSR Unit |───────────>|    |  |    +-------+   |  |   ^  |               |
  |  mstatus |            |    |  |     ^  ^  ^    |  |   |  |pmp_faults     |
  |  mepc    | pmpcfg0,   |    |  | pmp |pac|ktrr  |  |   |  |               |
  |  mcause  | pmpaddr    |    |  |     |  | |  |  |  |   |  v               |
  |  mtvec   |────────────┤    |  | +---+--+-+--+--+---+------+             |
  |  mtval   |            |    |  | |       Fault Merge        |             |
  |  mscratch| csr_rdata  |    |  | +--------------------------+             |
  |  pmpcfg0 |──────┐     |    |  |          |                               |
  |  pmpaddr |      |     |    |  |          | trap_cause_merged             |
  |  pac_keys|──┐   |     |    |  |          |                               |
  | ktrr_regs|──┤   |     |    |  |          |                               |
  +----------+<─┤───┤─────┤────┘  |          |                               |
       ^        |   |     |       └──────────┘                               |
       |        v   v     |                                                  |
       |  +----------+    |  +----------+   rd3   +----------+               |
       |  |          |    |  | Reg File |─────--─>|  QARMA   |  pac_result   |
       └──| ResultMux|────┤  | 32 x 32  | rd1──-->|  64-5    |──────┐        |
          +----------+    |  | +3rd port |  rd2──>| 14 cyc   |      │        |
                          |  +----------+        +-----------+      │        |
                          |        stall <──── ~valid & is_pac      │        |
                          +───────────────────┬─────────────────────┘────────+
                                              | mem_addr
                                    +---------+---------+
                                    v                   v
                              +----------+        +----------+
                              |   DMEM   |        |   UART   |
                              |  64 KiB  |        |  TX/RX   |
                              +----------+        +----------+
```

### PC Priority

```
if trap_taken  => trap_pc  (mtvec or mepc)
else if branch => pc_target
else           => pc + 4
```

### Result Mux

| result_src | Source |
|------------|--------|
| 000 | ALU result |
| 001 | Load value |
| 010 | PC + 4 (JAL/JALR link) |
| 011 | PC + imm (AUIPC) |
| 100 | Immediate (LUI) |
| 101 | CSR read value |
| 110 | PAC result (QARMA-64 lower 32 bits) |

## Modules

### `Top.sv`
Top-level. Connects CPU to memory and I/O. Loads `imem.hex` and `dmem.hex` at init.
Handles UART TX/RX and the exit mechanism. IMEM supports both read and write paths
(KTRR enforcement happens in the CPU, not here).

### `riscv_cpu.sv`
CPU core. PC logic, immediate decoder, controller/ALU/regfile/CSR/PMP/QARMA instantiation,
load extension (LB/LH/LBU/LHU alignment), store alignment (SB/SH byte enables),
branch resolution, PMP + PAC + KTRR fault merge, result mux, and stall gating.
QARMA-64 engine stalls the pipeline for 14 cycles during PAC/AUT instructions.
KTRR fault check is inline (two comparators, no separate module).

### `controller.sv`
Combinational decoder. Inputs: opcode, funct3, funct7, funct12_0, priv_mode.
Outputs: all control signals (reg_write, result_src, alu_src, alu_ctrl, branch, jump,
jalr, is_store, is_csr, is_pac, trap_cause, is_mret). ALU decoder maps funct3/funct7
to 5-bit ALU control.

### `alu.sv`
5-bit control, 32-bit datapath. Base ops (ADD–SLTU) at `0_xxxx`, M-extension at `1_0xxx`
(funct3 maps directly). 64-bit intermediates for MULH variants.
Division-by-zero and signed overflow handled per RISC-V spec.

### `reg_file.sv`
32×32-bit register file. 2 async read ports (rs1, rs2) + 1 extra read port (rd_addr2/rd3
for AUT instructions). Sync write. x0 hardwired to zero.

### `csr_unit.sv`
CSR registers + trap/privilege logic. Handles trap entry (save state → M-mode),
MRET (restore state from MPP), and CSR read-modify-write operations.
Holds PMP registers (pmpcfg0, pmpaddr0–3) with lock bit enforcement,
PAC key registers (pac_ia_key0–3, pac_da_key0–3),
and KTRR registers (ktrr_base, ktrr_limit, ktrr_lock) with write-once lock.

### `qarma64.sv`
Multi-cycle QARMA-64-5 tweakable block cipher engine for PAC. 14-cycle iterative
implementation: initial whitening → 5 forward rounds → pseudo-reflector (2 cycles) →
5 backward rounds → final whitening. Pseudo-reflector split across 2 cycles to
keep combinational depth uniform. Uses involutory S-box (σ₀) and involutory
MixColumns (Midori-64 style). Driven by `start` pulse, asserts `valid` for
1 cycle when result is ready.

### `pmp_unit.sv`
Combinational PMP checker. 4 entries, checks PC (fetch) and ALU result (load/store)
against pmpaddr/pmpcfg. Faults merge with controller trap causes in `riscv_cpu.sv`.

## Memory Map

| Address | Size | Description |
|---------|------|-------------|
| `0x00000000` | 64 KiB | IMEM — instruction memory (read-write, loaded from `imem.hex`, lockable via KTRR) |
| `0x10000000` | 4 B | EXIT — write here to terminate simulation (value = return code) |
| `0x40000000` | 4 B | UART data — write: TX byte, read: RX byte |
| `0x40000004` | 4 B | UART LSR — bit 0: RX ready, bit 5: TX ready (always 1) |
| `0x80000000` | 64 KiB | DMEM — data memory (read-write, loaded from `dmem.hex`) |

### UART

- **TX**: Write a byte to `0x40000000`. Output via `$write`/`$fflush`.
- **RX**: Poll LSR bit 0. When set, read byte from `0x40000000`. Reading clears the ready flag.
  Input comes from stdin via DPI-C `dpi_getchar()` (non-blocking, raw terminal mode).

## Privilege Modes

Two modes: **Machine (M)** and **User (U)**.

| Feature | M-mode | U-mode |
|---------|--------|--------|
| CSR access | Allowed | Traps (illegal instruction) |
| MRET | Allowed | Traps (illegal instruction) |
| ECALL cause | mcause = 11 | mcause = 8 |
| Memory access | Full (unless locked PMP entry) | PMP-enforced |

CPU starts in M-mode after reset.

### Trap Entry

When `trap_cause != 0`:

1. `mepc ← PC` (faulting instruction address)
2. `mcause ← trap_cause`
3. `mstatus.MPP ← current privilege`
4. `mstatus.MPIE ← mstatus.MIE`
5. `mstatus.MIE ← 0`
6. `privilege ← M`
7. `PC ← mtvec`

### MRET

1. `privilege ← mstatus.MPP`
2. `mstatus.MIE ← mstatus.MPIE`
3. `mstatus.MPIE ← 1`
4. `mstatus.MPP ← U`
5. `PC ← mepc`

## CSRs

| Address | Name | Description |
|---------|------|-------------|
| `0x300` | mstatus | MIE [3], MPIE [7], MPP [12:11] |
| `0x305` | mtvec | Trap vector base (reset: `0x100`) |
| `0x340` | mscratch | Scratch register for trap handlers |
| `0x341` | mepc | Exception PC |
| `0x342` | mcause | Trap cause code |
| `0x343` | mtval | Trap value (faulting address for access faults) |
| `0x3A0` | pmpcfg0 | PMP config for entries 0–3 (4 packed bytes) |
| `0x3B0` | pmpaddr0 | PMP address register 0 |
| `0x3B1` | pmpaddr1 | PMP address register 1 |
| `0x3B2` | pmpaddr2 | PMP address register 2 |
| `0x3B3` | pmpaddr3 | PMP address register 3 |
| `0x7C0` | pac_ia_key0 | PAC IA key bits [31:0] (M-mode only) |
| `0x7C1` | pac_ia_key1 | PAC IA key bits [63:32] |
| `0x7C2` | pac_ia_key2 | PAC IA key bits [95:64] |
| `0x7C3` | pac_ia_key3 | PAC IA key bits [127:96] |
| `0x7C4` | pac_da_key0 | PAC DA key bits [31:0] (M-mode only) |
| `0x7C5` | pac_da_key1 | PAC DA key bits [63:32] |
| `0x7C6` | pac_da_key2 | PAC DA key bits [95:64] |
| `0x7C7` | pac_da_key3 | PAC DA key bits [127:96] |
| `0x7C8` | ktrr_base | KTRR region start address (byte, inclusive) |
| `0x7C9` | ktrr_limit | KTRR region end address (byte, exclusive) |
| `0x7CA` | ktrr_lock | Bit 0: locked (write-once, cannot clear until reset) |

### Trap Causes

| Code | Cause |
|------|-------|
| 1 | Instruction access fault (PMP) |
| 2 | Illegal instruction |
| 3 | Breakpoint (EBREAK) |
| 5 | Load access fault (PMP) |
| 7 | Store/AMO access fault (PMP) |
| 8 | Environment call from U-mode |
| 11 | Environment call from M-mode |
| 18 | PAC authentication failure (AUTIA/AUTDA mismatch) |
| 24 | KTRR store fault (write to locked region) |

## Physical Memory Protection (PMP)

4 PMP entries. M-mode configures regions + permissions; U-mode access is checked
against them on every fetch/load/store.

### pmpcfg0 Entry Format

Each entry = one byte of `pmpcfg0` (entry 0 = bits [7:0], entry 3 = bits [31:24]).

| Bit | Field | Description |
|-----|-------|-------------|
| 7 | L | Lock — when set, entry is locked and also enforced for M-mode |
| 6:5 | — | Reserved (WIRI) |
| 4:3 | A | Address matching mode |
| 2 | X | Execute permission |
| 1 | W | Write permission |
| 0 | R | Read permission |

### Address Matching Modes

| A | Mode | Matching |
|---|------|----------|
| 00 | OFF | Entry disabled |
| 01 | TOR | Top of Range: `pmpaddr[i-1] <= addr[31:2] < pmpaddr[i]` (entry 0 lower bound = 0) |
| 10 | NA4 | Naturally Aligned 4-byte: `addr[31:2] == pmpaddr[i]` |
| 11 | NAPOT | Naturally Aligned Power-of-Two: masked comparison using `pmpaddr` encoding |

### NAPOT Address Encoding

For a region of size `2^n` bytes at base address `base`:
`pmpaddr = (base >> 2) | ((1 << (n-2)) - 1)`

### Matching & Permissions

- First matching entry wins (priority encoder, entry 0 = highest).
- U-mode no match: fault if any entry is active (A != OFF), otherwise allow (backward compat).
- M-mode no match: always allow.
- Lock (L=1): M-mode also subject to RWX bits.

### Faults

| Fault | mcause | mtval |
|-------|--------|-------|
| Instruction access | 1 | PC |
| Load access | 5 | Address |
| Store/AMO access | 7 | Address |

Priority: `instr fault (1) > controller trap > PAC auth fail (18) > KTRR fault (24) > load fault (5) > store fault (7)`

### Lock Bit Writes

- `pmpcfg0`: bytes with L=1 are read-only.
- `pmpaddr[i]`: blocked if entry i locked, or if entry i+1 uses TOR and is locked.

## Stall Infrastructure

A `stall` signal in `riscv_cpu.sv` gates PC updates, register writes, store operations,
and CSR writes. Driven by PAC instructions: `stall = is_pac & ~qarma_valid`.
QARMA-64 takes 14 cycles, so the pipeline freezes for 13 cycles (stall high on cycles 0–12,
valid on cycle 13).

## Pointer Authentication Code (PAC)

Signs and verifies pointers using QARMA-64-5 (tweakable block cipher).
Each pointer gets a cryptographic tag tied to a context value, so corrupted pointers fail verification.

### Instructions

Custom-0 opcode space (`0x0B`), R-type encoding. Allowed in both M-mode and U-mode.

| funct7 | funct3 | Mnemonic | Operation |
|--------|--------|----------|-----------|
| 0000000 | 000 | PACIA rd,rs1,rs2 | rd = PAC(rs1, rs2, key_ia) |
| 0000000 | 001 | PACDA rd,rs1,rs2 | rd = PAC(rs1, rs2, key_da) |
| 0000001 | 000 | AUTIA rd,rs1,rs2 | trap(18) if PAC(rs1, rs2, key_ia) != rd |
| 0000001 | 001 | AUTDA rd,rs1,rs2 | trap(18) if PAC(rs1, rs2, key_da) != rd |

- **PACIA/PACDA**: Compute a 32-bit authentication code from pointer (rs1), modifier (rs2), and key. Result written to rd.
- **AUTIA/AUTDA**: Recompute the PAC and compare against rd. If mismatch, trap with mcause=18 and mtval=rs1.
- funct7[0]: 0 = sign (PAC), 1 = authenticate (AUT)
- funct3[0]: 0 = IA key, 1 = DA key

### QARMA-64-5

64-bit tweakable block cipher. Plaintext = `{32'b0, pointer}`, tweak = `{32'b0, modifier}`,
key = 128-bit from PAC CSRs. Result: lower 32 bits of ciphertext.

14-cycle iterative pipeline (pseudo-reflector split across 2 cycles for uniform timing):
1. Initial whitening: `IS = P ^ w0`
2. Forward rounds 0–4: AddTweakey → ShuffleCells → MixColumns (skip round 0) → SubCells
3. Pseudo-reflector part 1: AddTweakey(k0) → SubCells → MixColumns
4. Pseudo-reflector part 2: SubCells → AddTweakey(k1)
5. Backward rounds 4–0: SubCells → MixColumns (skip round 4) → InvShuffleCells → AddTweakey
6. Final whitening: `C = IS ^ w1`

Properties: involutory S-box (σ₀ = σ₀⁻¹), involutory MixColumns (M = M⁻¹).

### PAC Key CSRs

128-bit keys split across 4 CSRs each. Layout: `k0 = {key1, key0}` (core), `w0 = {key3, key2}` (whitening).
M-mode only — U-mode access traps as illegal instruction. U-mode can execute PAC/AUT instructions
(keys are used internally but not readable).

## Kernel Text Read-Only Region (KTRR)

Locks a physical address range so nothing can write to it — not even M-mode.
Once locked, stores to the protected range trap with mcause=24. Loads and fetches still work.

### CSRs

| Address | Name | Description |
|---------|------|-------------|
| `0x7C8` | ktrr_base | Start address of locked region (byte address, inclusive) |
| `0x7C9` | ktrr_limit | End address of locked region (byte address, exclusive) |
| `0x7CA` | ktrr_lock | Bit 0: locked. Write-once — once set, cannot be cleared until reset. |

### Behavior

- **Before lock**: All three CSRs are freely writable. IMEM is read-write.
- **After lock** (`ktrr_lock[0] == 1`):
  - Writes to `ktrr_base`, `ktrr_limit`, and `ktrr_lock` are silently ignored.
  - Stores to addresses in `[ktrr_base, ktrr_limit)` trap with mcause=24, mtval=faulting address.
  - Loads and instruction fetches from the region are unaffected.
- **Reset**: All three registers reset to zero (unlocked, no region defined).
- **Note**: If `ktrr_base >= ktrr_limit`, the range is empty and no stores are blocked.

### Fault

| Fault | mcause | mtval |
|-------|--------|-------|
| KTRR store | 24 | Faulting store address |

KTRR sits after PAC and before PMP data faults in the priority chain. It only fires on stores.

## Linker Layout

```
IMEM  0x00000000  .text.start (_start first), .text*
DMEM  0x80000000  .rodata*, .data*, .bss*
Stack 0x80010000  grows downward
```
