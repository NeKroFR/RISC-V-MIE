.section .text.start
.global _start
 .global main

_start:
    # Set up stack pointer (64 KB)
    li sp, 0x00010000

    # Clear BSS
    la a0, _bss_start
    la a1, _bss_end
bss_loop:
    beq a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_loop
bss_done:

    call main
