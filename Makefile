PROGRAM ?= programs/hello_world

all: sim

build-program:
	@echo "Building program in $(PROGRAM)..."
	cd $(PROGRAM) && make
	@echo "Copying hex files to root..."
	cp $(PROGRAM)/imem.hex .
	cp $(PROGRAM)/dmem.hex .

sim: build-program
	@echo "Copying hex files to sim/verilator..."
	cp imem.hex dmem.hex sim/verilator/
	@echo "Running Verilator simulation..."
	cd sim/verilator && make sim

clean:
	cd $(PROGRAM) && make clean
	rm -f imem.hex dmem.hex
	cd sim/verilator && make clean

.PHONY: all build-program sim clean
