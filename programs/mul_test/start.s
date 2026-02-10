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
    call main
_exit:
    li a1, 0x10000000
    sw a0, 0(a1)
