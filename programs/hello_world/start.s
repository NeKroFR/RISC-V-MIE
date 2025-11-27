.section .text.start
.global _start
.global main

_start:
    # Set up stack at top of 64 KiB DMEM (0x80010000)
    li sp, 0x80010000

    # Clear BSS (0x8000xxxx range)
    la a0, _bss_start
    la a1, _bss_end
bss_loop:
    beq a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_loop
bss_done:
    call main
