#include "VTop.h"
#include "verilated.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VTop* top = new VTop;

    // 0: only print on adress 0x80000000
    // 1: debug prints
    top->verbosity = 1;

    // RESET
    top->clk = 0;
    top->reset = 1;
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
    }
    top->reset = 0;

    // Run simulation for 1K cycles
    int max_cycles = 1000;
    int cycle = 0;
    while (cycle < max_cycles) {
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        cycle++;
    }

    delete top;
    return 0;
}
