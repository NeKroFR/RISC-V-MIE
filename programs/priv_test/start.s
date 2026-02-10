.section .text.start
.global _start
.global main

_start:
    li sp, 0x80010000

    la a0, _bss_start
    la a1, _bss_end
bss_loop:
    beq a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_loop
bss_done:
    j main_entry

# === Trap handler at 0x100 (mtvec) ===
.org 0x100
.global trap_handler
trap_handler:
    # Save t0-t2 on stack
    addi sp, sp, -12
    sw t0, 0(sp)
    sw t1, 4(sp)
    sw t2, 8(sp)

    csrr t0, mcause

    # Check for "exit to M-mode" syscall: mcause==8 (U-mode ECALL) && a0==1
    # Do this BEFORE storing mcause so exit doesn't overwrite the test result
    li t1, 8
    bne t0, t1, store_mcause
    li t1, 1
    beq a0, t1, exit_handler

store_mcause:
    # Store mcause at 0x80000100 for C code to read
    lui t1, 0x80000
    sw t0, 0x100(t1)
    j normal_return

exit_handler:

    # --- Exit syscall: return to M-mode ---
    # Load saved M-mode return address from 0x80000104
    lui t1, 0x80000
    lw t0, 0x104(t1)
    csrw mepc, t0
    # Set MPP = M-mode (bits 12:11 = 11 = 0x1800)
    li t0, 0x1800
    csrs mstatus, t0
    j trap_done

normal_return:
    # Advance mepc past trapping instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

trap_done:
    lw t0, 0(sp)
    lw t1, 4(sp)
    lw t2, 8(sp)
    addi sp, sp, 12
    mret

main_entry:
    call main
_exit:
    li a1, 0x10000000
    sw a0, 0(a1)
