#include <stdint.h>

char dmem[] = "[.data] Hello from RISC-V!\n";

void *memcpy(void *dest, const void *src, uint32_t n) {
    uint8_t *d = dest;
    const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

void print(const char *str) {
    while (*str) {
        *(volatile uint32_t*)0x80000000 = *str++;
    }
}

int main() {
    char local[] = "[.text] Hello from RISC-V!\n";
    print(local);
    print(dmem);
    return 0;
}
