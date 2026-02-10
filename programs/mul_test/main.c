#include <stdint.h>

#define UART_ADDR (*(volatile uint32_t *)0x40000000)

void *memcpy(void *dest, const void *src, uint32_t n) {
    uint8_t *d = dest;
    const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

void print(const char *s) {
    while (*s) UART_ADDR = *s++;
}

void print_hex(unsigned int x) {
    const char h[] = "0123456789abcdef";
    for (int i = 7; i >= 0; i--)
        UART_ADDR = h[(x >> (i * 4)) & 0xf];
}

static int pass_count = 0;
static int fail_count = 0;

void check(const char *name, uint32_t got, uint32_t expected) {
    print(name);
    print(" got=0x");
    print_hex(got);
    if (got == expected) {
        print(" OK\n");
        pass_count++;
    } else {
        print(" FAIL (exp=0x");
        print_hex(expected);
        print(")\n");
        fail_count++;
    }
}

int main() {
    print("=== M-Extension Test ===\n");

    // MUL: lower 32 bits of product
    check("[MUL] 7*13", (uint32_t)(7 * 13), 91);
    check("[MUL] -3*11", (uint32_t)(-3 * 11), (uint32_t)-33);
    check("[MUL] 0x10000*0x10000", 0x10000u * 0x10000u,  0); // overflow, low 32=0

    // MULH: upper 32 bits, signed*signed
    int32_t a = -1, b = -1;
    int64_t prod_ss = (int64_t)a * (int64_t)b;
    check("[MULH] -1*-1",     (uint32_t)(prod_ss >> 32), 0);

    a = 0x40000000; b = 4;
    prod_ss = (int64_t)a * (int64_t)b;
    check("[MULH] 0x40000000*4", (uint32_t)(prod_ss >> 32), 1);

    // DIV: signed division
    check("[DIV] 20/3", (uint32_t)(20 / 3),  6);
    check("[DIV] -20/3", (uint32_t)(-20 / 3), (uint32_t)-6);

    // DIVU: unsigned division
    check("[DIVU] 100/7", 100u / 7u, 14);

    // DIV by zero: spec says result = -1 (all ones)
    uint32_t div_zero;
    __asm__ volatile("div %0, %1, %2" : "=r"(div_zero) : "r"(42), "r"(0));
    check("[DIV] 42/0", div_zero, 0xFFFFFFFF);

    // DIVU by zero: spec says result = 0xFFFFFFFF
    __asm__ volatile("divu %0, %1, %2" : "=r"(div_zero) : "r"(42), "r"(0));
    check("[DIVU] 42/0", div_zero, 0xFFFFFFFF);

    // REM: signed remainder
    check("[REM] 20%3", (uint32_t)(20 % 3), 2);
    check("[REM] -20%3", (uint32_t)(-20 % 3), (uint32_t)-2);

    // REMU: unsigned remainder
    check("[REMU] 100%7", 100u % 7u, 2);

    // REM by zero: spec says result = dividend
    uint32_t rem_zero;
    __asm__ volatile("rem %0, %1, %2" : "=r"(rem_zero) : "r"(42), "r"(0));
    check("[REM] 42%0", rem_zero, 42);

    // DIV overflow: INT_MIN / -1 = INT_MIN
    int32_t int_min = (int32_t)0x80000000;
    int32_t neg_one = -1;
    int32_t div_ovf;
    __asm__ volatile("div %0, %1, %2" : "=r"(div_ovf) : "r"(int_min), "r"(neg_one));
    check("[DIV] INT_MIN/-1", (uint32_t)div_ovf, 0x80000000);

    // Summary
    print("\n");
    print_hex(pass_count);
    print(" passed, ");
    print_hex(fail_count);
    print(" failed\n");
    print("=== Done ===\n");
    return fail_count;
}
