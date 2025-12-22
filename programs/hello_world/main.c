#include <stdint.h>

#define UART_ADDR     (*(volatile uint32_t*)0x40000000)
#define UART_LSR    (*(volatile uint32_t*)0x40000004)

char dmem[] = "[.data] Hello from RISC-V!\n";

void *memcpy(void *dest, const void *src, uint32_t n) {
    uint8_t *d = dest;
    const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

void print(const char *str) {
    while (*str) {
        UART_ADDR = *str++;
    }
}

int main() {
    char local[] = "[.text] Hello from RISC-V!\n";
    print(local);
    print(dmem);
    return 0;
}
