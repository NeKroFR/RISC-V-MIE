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
| **CSRs** | mstatus, mtvec, mepc, mcause, mtval, mscratch, pmpcfg0, pmpaddr0–3, pac_ia_key0–3, pac_da_key0–3 |
| **Memory** | 64 KiB IMEM + 64 KiB DMEM (Harvard) |
| **I/O** | UART (TX/RX via DPI-C) |

See [docs/architecture.md](docs/architecture.md) for the full architecture documentation.

## Security Features

| Status | Feature | Apple Equivalent | Purpose |
| :---:  | ------- | ---------------- | ------- |
| ✅ | **PAC** | Pointer Auth | Cryptographically signs pointers to prevent ROP/JOP attacks. QARMA-64-5 cipher, 14-cycle latency. |
| ❌ | **APRR** | APRR | **Access Protection Rerouting.** Allows the kernel to restrict its own permissions (e.g., make pages Read-Only) without TLB flushes. |
| ❌ | **GXF** | GXF / Guarded Mode | **Guarded Exception Flag.** Provides a secure execution mode with separate register states, acting as a hardware barrier between standard kernel and a higher-privilege guarded context. |
| ✅ | **PMP** | — | **Physical Memory Protection.** 4 hardware entries enforce R/W/X permissions per region. M-mode configures, U-mode is restricted. Lock bit extends enforcement to M-mode. |
| ❌ | **KTRR** | KTRR / KIP | **Kernel Text Read-Only Region.** A hard-locked physical memory range that becomes immutable post-boot, preventing kernel patches. |
| ❌ | **SPRR** | SPRR | **Secure Permission Remapping.** Remaps page table permission bits dynamically. Works alongside APRR to enforce granular access controls. |
| ❌ | **MTE** | Memory Tagging | Assigns "colors" (tags) to memory blocks and pointers to prevent Use-After-Free and Buffer Overflows. |
| ❌ | **EMTE** | *Enhanced MTE* | **Experimental.** Extends MTE with synchronous tag checking and canonical validation to block overflows without async faults. |
