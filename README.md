# RISC-V MIE

This repository implements **Apple's Memory Integrity Enforcement** on a custom **RV32IM** core with **M/U privilege modes**. The goal is to replicate the hardware-level security primitives found in Apple silicon (M1/M2/M3) within the RISC-V ecosystem.

**Note:** We excluded features related to Apple's operating systems (like the XNU kernel), as our focus is on hardware primitives in a generic way.

## CPU

Custom RV32IM core simulated via Verilator. Stall-capable datapath for multi-cycle operations.

| Feature | Details |
| ------- | ------- |
| **ISA** | RV32IM + Zicsr + PAC (custom-0) |
| **Privilege** | M-mode + U-mode (trap entry/MRET, privilege enforcement) |
| **PMP** | 4 entries — TOR, NA4, NAPOT modes; lock bit; U-mode enforcement |
| **CSRs** | mstatus, mtvec, mepc, mcause, mtval, mscratch, pmpcfg0, pmpaddr0–3, pac_ia_key0–3, pac_da_key0–3, ktrr_base, ktrr_limit, ktrr_lock |
| **Memory** | 64 KiB IMEM + 64 KiB DMEM (Harvard) |
| **I/O** | UART (TX/RX via DPI-C) |

See [docs/architecture.md](docs/architecture.md) for the full architecture documentation.

## Security Features

| Status | Feature | Apple Equivalent | Purpose |
| :---:  | ------- | ---------------- | ------- |
| ✅ | **PAC** | Pointer Auth | Signs pointers with QARMA-64-5 to kill ROP/JOP. 14-cycle latency. |
| ❌ | **APRR** | APRR | Lets the kernel tighten its own permissions (e.g. make pages RO) without TLB flushes. |
| ❌ | **GXF** | GXF / Guarded Mode | Separate execution context with its own register state, walled off from the normal kernel. |
| ✅ | **PMP** | — | 4 hardware entries enforce R/W/X per region. M-mode configures, U-mode is restricted. Lock bit applies to M-mode too. |
| ✅ | **KTRR** | KTRR / KIP | Locks a physical memory range as immutable post-boot. Not even M-mode can write to it. |
| ❌ | **SPRR** | SPRR | Remaps page table permission bits at runtime. Works with APRR for fine-grained control. |
| ❌ | **MTE** | Memory Tagging | Tags memory and pointers with "colors" to catch UAF and buffer overflows. |
| ❌ | **EMTE** | *Enhanced MTE* | Extends MTE with synchronous tag checks and canonical validation. |
