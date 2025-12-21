#include "VTop.h"
#include "verilated.h"

extern "C" int dpi_getchar() {
    fflush(stdout);
    return getchar();
}

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
    // Run simulation
    long long cycle = 0;
    while (1) {
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        cycle++;
    }

    delete top;
    return 0;
}
