TARGET   := ktrr_test
SRCS     := main.c start.s

OBJS     := $(SRCS:.c=.o)
OBJS     := $(OBJS:.s=.o)

CC       := riscv64-unknown-elf-gcc
OBJCOPY  := riscv64-unknown-elf-objcopy

CFLAGS   := -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -nostdlib -Os -Wall -Wextra
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
	$(OBJCOPY) --only-section=.text* -O verilog --verilog-data-width=4 $< $@

dmem.hex: $(TARGET).elf
	$(OBJCOPY) --only-section=.rodata* --only-section=.data* \
	           --change-addresses=-0x80000000 \
	           -O verilog --verilog-data-width=4 $< $@ || \
	           echo "@00000000 00000000" > $@

clean:
	rm -f $(OBJS) $(TARGET).elf *.hex

.PHONY: all clean
