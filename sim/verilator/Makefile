TOP_MODULE = Top
RTL_DIR    = ../../src/rtl
V_SOURCES  = $(shell find $(RTL_DIR) -name '*.sv' | sort)

VERILATOR_FLAGS = -Wall --cc --exe --build -j 0 \
                  --top-module $(TOP_MODULE) \
                  -Wno-DECLFILENAME \
                  -Wno-WIDTHEXPAND \
                  -Wno-UNUSEDSIGNAL \
                  -Wno-PINMISSING \
                  --x-initial unique \
                  tb.cpp $(V_SOURCES)

sim:
	@echo "Found $(words $(V_SOURCES)) .sv files"
	verilator $(VERILATOR_FLAGS)
	@echo "Simulation running..."
	./obj_dir/V$(TOP_MODULE)

clean:
	rm -rf obj_dir/ *.vcd *.hex

.PHONY: sim clean
