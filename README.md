# RISC-V MIE

This repository aims to implement **Apple's Memory Integrity Enforcement** on a custom **RV32I** core. The goal is to replicate the hardware-level security primitives found in Apple (M1/M2/M3) within the RISC-V ecosystem.

**Note:** We excluded features related to Apple’s operating systems (like the XNU kernel for example), as our focus was on hardware primitives in a generic way.

**Disclaimer:** This project is currently in an early stage. For now, I am setting up the environment and implementing a working RV32I so I will then be able to easily implement those security features.

## 🔒 Security Features

| Status | Feature | Apple Equivalent | Purpose |
| :---:  | ------- | ---------------- | ------- |
| ❌ | **PAC** | Pointer Auth | Cryptographically signs pointers to prevent ROP/JOP attacks. |
| ❌ | **APRR** | APRR | **Access Protection Rerouting.** Allows the kernel to restrict its own permissions (e.g., make pages Read-Only) without TLB flushes. The hardware enabler for PPL. |
| ❌ | **GXF** | GXF / Guarded Mode | **Guarded Exception Flag.** Provides a secure execution mode with separate register states, acting as a hardware barrier between standard Kernel and a higher-privilege guarded context. |
| ❌ | **KTRR** | KTRR / KIP | **Kernel Text Read-Only Region.** A hard-locked physical memory range that becomes immutable post-boot, preventing kernel patches. |
| ❌ | **SPRR** | SPRR | **Secure Permission Remapping.** Remaps page table permission bits dynamically. Works alongside APRR to enforce granular access controls. |
| ❌ | **MTE** | Memory Tagging | Assigns "colors" (tags) to memory blocks and pointers to prevent Use-After-Free and Buffer Overflows. |
| ❌ | **EMTE** | *Enhanced MTE* | **Experimental.** Extends MTE with synchronous tag checking and canonical validation to block overflows without async faults. |
