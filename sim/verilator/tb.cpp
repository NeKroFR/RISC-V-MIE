#include "VTop.h"
#include "verilated.h"
#include <termios.h>

struct termios orig_termios;

void disableRawMode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void enableRawMode() {
    tcgetattr(STDIN_FILENO, &orig_termios);
    atexit(disableRawMode);
    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
}

extern "C" int dpi_getchar() {
    char c;
    if (read(STDIN_FILENO, &c, 1) > 0)
        return c;
    return -1;
}

int main(int argc, char** argv) {
    enableRawMode();
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
    long long cycles = 0;
    while (1) {
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        cycles++;
    }

    delete top;
    return 0;
}
