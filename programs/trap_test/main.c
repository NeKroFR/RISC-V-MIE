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

static inline uint32_t read_mcause(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, mcause" : "=r"(val));
    return val;
}

static inline uint32_t read_mepc(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, mepc" : "=r"(val));
    return val;
}

int main() {
    uint32_t mcause_val;

    print("=== Trap Test ===\n");

    // Test 1: ECALL
    print("[1] ECALL... ");
    __asm__ volatile("ecall");
    mcause_val = read_mcause();
    print("mcause=0x");
    print_hex(mcause_val);
    if (mcause_val == 11)
        print(" OK\n");
    else
        print(" FAIL\n");

    // Test 2: EBREAK
    print("[2] EBREAK... ");
    __asm__ volatile("ebreak");
    mcause_val = read_mcause();
    print("mcause=0x");
    print_hex(mcause_val);
    if (mcause_val == 3)
        print(" OK\n");
    else
        print(" FAIL\n");

    // Test 3: CSR read/write (write mtvec, read it back)
    print("[3] CSR R/W... ");
    uint32_t mtvec_val;
    __asm__ volatile("csrr %0, mtvec" : "=r"(mtvec_val));
    print("mtvec=0x");
    print_hex(mtvec_val);
    if (mtvec_val == 0x100)
        print(" OK\n");
    else
        print(" FAIL\n");

    // Test 4: CSR write + readback
    print("[4] CSR write... ");
    __asm__ volatile("csrw mtvec, %0" :: "r"(0x200));
    __asm__ volatile("csrr %0, mtvec" : "=r"(mtvec_val));
    print("mtvec=0x");
    print_hex(mtvec_val);
    // Restore original mtvec
    __asm__ volatile("csrw mtvec, %0" :: "r"(0x100));
    if (mtvec_val == 0x200)
        print(" OK\n");
    else
        print(" FAIL\n");

    // Test 5: CSRRS (set bits) — clear mstatus first (trap cycles modify MPIE/MPP)
    print("[5] CSRRS... ");
    __asm__ volatile("csrw mstatus, %0" :: "r"(0));
    uint32_t old_mstatus;
    __asm__ volatile("csrrs %0, mstatus, %1" : "=r"(old_mstatus) : "r"(0x8));
    uint32_t new_mstatus;
    __asm__ volatile("csrr %0, mstatus" : "=r"(new_mstatus));
    print("mstatus=0x");
    print_hex(new_mstatus);
    if (old_mstatus == 0x0 && new_mstatus == 0x8)
        print(" OK\n");
    else
        print(" FAIL\n");

    // Test 6: CSRRC (clear bits)
    print("[6] CSRRC... ");
    __asm__ volatile("csrrc %0, mstatus, %1" : "=r"(old_mstatus) : "r"(0x8));
    __asm__ volatile("csrr %0, mstatus" : "=r"(new_mstatus));
    print("old=0x");
    print_hex(old_mstatus);
    print(" new=0x");
    print_hex(new_mstatus);
    if (old_mstatus == 0x8 && new_mstatus == 0x0)
        print(" OK\n");
    else
        print(" FAIL\n");

    print("=== Done ===\n");
    return 0;
}
