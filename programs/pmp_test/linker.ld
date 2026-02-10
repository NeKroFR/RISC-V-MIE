ENTRY(_start)

MEMORY
{
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rw) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))
        *(.text*)
    } > IMEM

    .data : {
        _data_start = .;
        *(.rodata*)
        *(.data*)
        _data_end = .;
    } > DMEM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > DMEM

    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
