// Payload:
// 4141414141414141414141414141414141414141414141414141414141414141a0000000

#include <stddef.h>

#define UART_ADDR (*(volatile char *)0x40000000)
#define UART_LSR  (*(volatile char *)0x40000004)
#define LSR_RX_READY 0x01

void memcpy(void *dest, const void *src, size_t n) {
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (n--) *d++ = *s++;
}

void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

void print(const char *s) {
    while (*s) UART_ADDR = *s++;
}

void print_hex(unsigned int x) {
    char h[] = "0123456789abcdef";
    for (int i = 7; i >= 0; i--)
        UART_ADDR = h[(x >> (i * 4)) & 0xf];
}

int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

int input_hex(char *buf) {
    int i = 0;
    char c, h1, h2;

    while (1) {
        if (!(UART_LSR & LSR_RX_READY))
            continue;

        c = UART_ADDR;
        UART_ADDR = c;

        if (c == '\n' || c == '\r')
            return i;

        if (c == ' ')
            continue;

        h1 = c;
        if (hexval(h1) < 0)
            continue;

        while (!(UART_LSR & LSR_RX_READY));
        h2 = UART_ADDR;
        UART_ADDR = h2;

        if (hexval(h2) < 0)
            continue;

        buf[i++] = (hexval(h1) << 4) | hexval(h2);
    }
}

void print_poulet() {
    print("\n🐔 poulet\n");
}

void print_singe() {
    print("\n🐒 singe\n");
}

struct frame {
    char buf[32];
    void (*fp)();
};

void vuln() {
    struct frame f;

    f.fp = print_poulet;
    memset(f.buf, 0, sizeof(f.buf));

    print("\n[DEBUG]\n");
    print("buf     @ 0x"); print_hex((unsigned int)f.buf); print("\n");
    print("fp      @ 0x"); print_hex((unsigned int)&f.fp); print("\n");
    print("poulet  @ 0x"); print_hex((unsigned int)print_poulet); print("\n");
    print("singe   @ 0x"); print_hex((unsigned int)print_singe); print("\n");

    print("\nInput> ");
    input_hex(f.buf);

    print("\nCalling fp...\n");
    f.fp();
}

int main() {
    while (1) vuln();
}
