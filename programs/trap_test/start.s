.section .text.start
.global _start
.global main

_start:
    # Set up stack at top of 64 KiB DMEM (0x80010000)
    li sp, 0x80010000

    # Clear BSS
    la a0, _bss_start
    la a1, _bss_end
bss_loop:
    beq a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_loop
bss_done:
    j main_entry

# --- Trap handler at address 0x100 (mtvec default) ---
.org 0x100
.global trap_handler
trap_handler:
    # Save t0 on stack
    addi sp, sp, -4
    sw t0, 0(sp)

    # Read mepc, advance past trapping instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

    # Restore t0
    lw t0, 0(sp)
    addi sp, sp, 4

    # Return from trap
    mret

main_entry:
    call main
_exit:
    li a1, 0x10000000
    sw a0, 0(a1)
