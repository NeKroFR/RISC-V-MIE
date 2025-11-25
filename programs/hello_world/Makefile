TARGET  := hello_world
SRCS    := main.c start.s

OBJS     := $(SRCS:.c=.o)
OBJS     := $(OBJS:.s=.o)

CC       := riscv64-unknown-elf-gcc
OBJCOPY  := riscv64-unknown-elf-objcopy

CFLAGS   := -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -Os -Wall
CFLAGS   += -mno-relax
LDFLAGS  := -T linker.ld -Wl,--no-relax -Wl,-m,elf32lriscv

all: imem.hex dmem.hex

$(TARGET).elf: $(OBJS) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.s
	$(CC) $(CFLAGS) -c $< -o $@

imem.hex: $(TARGET).elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

dmem.hex: $(TARGET).elf
	-$(OBJCOPY) --dump-section .data=/dev/stdout $< 2>/dev/null | xxd -p | fold -w8 > $@ || echo "" > $@

clean:
	rm -f $(OBJS) $(TARGET).elf *.hex

.PHONY: all clean
