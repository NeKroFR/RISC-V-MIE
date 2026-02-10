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
  +----------+          │  |  |            |          | |               │    |
  | PC Mux   |         └──┤   +------------+   rd1,rd2| |alu_result     │    |
  | tr/br/+4 |            |    |  ^  |             ^  | |               │    |
  +----------+            |    |  |  |trap_cause   |  | v               │    |
       ^                  |    |  |  |   +-------+ |  | +----------+    │    |
       |   trap_pc        |    |  |  └──>| Fault | |  | |   PMP    |<───┘    |
       |                  |    |  |      | Merge | |  | | 4 entries |        |
  +----------+ priv_mode  |    |  |      +-------+ |  | +----------+         |
  | CSR Unit |───────────>|    |  |          ^     |  |   ^  |               |
  |  mstatus |            |    |  |  pmp_    |     |  |   |  |pmp_faults     |
  |  mepc    | pmpcfg0,   |    |  |  faults  |     |  |   |  |               |
  |  mcause  | pmpaddr    |    |  |          |     |  |   |  v               |
  |  mtvec   |────────────┤    |  |     +----+-----+--+---+------+           |
  |  mtval   |            |    |  |     |    Fault Merge         |           |
  |  mscratch| csr_rdata  |    |  |     +------------------------+           |
  |  pmpcfg0 |──────┐     |    |  |          |                               |
  |  pmpaddr |      |     |    |  |          | trap_cause_merged             |
  +----------+<─────┤─────┤────┘  |          |                               |
       ^            |     |       └──────────┘                               |
       |            v     |                                                  |
       |     +----------+ |  +----------+                                    |
       └─────| ResultMux|─┤  | Reg File |                                    |
             +----------+ |  | 32 x 32  |                                    |
                          |  +----------+                                    |
                          +---────────────────┬──────────────────────────────+
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

## Modules

### `Top.sv`
Top-level. Connects CPU to memory and I/O. Loads `imem.hex` and `dmem.hex` at init.
Handles UART TX/RX and the exit mechanism.

### `riscv_cpu.sv`
CPU core. PC logic, immediate decoder, controller/ALU/regfile/CSR/PMP instantiation,
load extension (LB/LH/LBU/LHU alignment), store alignment (SB/SH byte enables),
branch resolution, PMP fault merge, result mux, and stall gating.

### `controller.sv`
Combinational decoder. Inputs: opcode, funct3, funct7, funct12_0, priv_mode.
Outputs: all control signals (reg_write, alu_ctrl, branch, jump, is_store, is_csr,
trap_cause, is_mret). ALU decoder maps funct3/funct7 to 5-bit ALU control.

### `alu.sv`
5-bit control, 32-bit datapath. Base ops (ADD–SLTU) at `0_xxxx`, M-extension at `1_0xxx`
(funct3 maps directly). 64-bit intermediates for MULH variants.
Division-by-zero and signed overflow handled per RISC-V spec.

### `reg_file.sv`
32×32-bit register file. Async read, sync write. x0 hardwired to zero.

### `csr_unit.sv`
CSR registers + trap/privilege logic. Handles trap entry (save state → M-mode),
MRET (restore state from MPP), and CSR read-modify-write operations.
Also holds the PMP registers (pmpcfg0, pmpaddr0–3) with lock bit enforcement.

### `pmp_unit.sv`
Combinational PMP checker. 4 entries, checks PC (fetch) and ALU result (load/store)
against pmpaddr/pmpcfg. Faults merge with controller trap causes in `riscv_cpu.sv`.

## Memory Map

| Address | Size | Description |
|---------|------|-------------|
| `0x00000000` | 64 KiB | IMEM — instruction memory (read-only, loaded from `imem.hex`) |
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

Priority: `instr fault (1) > controller trap > load fault (5) > store fault (7)`

### Lock Bit Writes

- `pmpcfg0`: bytes with L=1 are read-only.
- `pmpaddr[i]`: blocked if entry i locked, or if entry i+1 uses TOR and is locked.

## Stall Infrastructure

A `stall` signal in `riscv_cpu.sv` gates PC updates, register writes, store operations,
and CSR writes. Currently tied to `0` — will be driven by multi-cycle units
(e.g., multi-cycle divider, memory wait states) once timing constraints require it.

## Linker Layout

```
IMEM  0x00000000  .text.start (_start first), .text*
DMEM  0x80000000  .rodata*, .data*, .bss*
Stack 0x80010000  grows downward
```
