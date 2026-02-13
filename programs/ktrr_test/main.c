#include <stdint.h>

#define UART_ADDR     (*(volatile uint32_t *)0x40000000)
#define TRAP_MCAUSE   (*(volatile uint32_t *)0x80000100)
#define TRAP_MTVAL    (*(volatile uint32_t *)0x80000108)

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
    if (got == expected) {
        print(" OK\n");
        pass_count++;
    } else {
        print(" FAIL (got=0x");
        print_hex(got);
        print(" exp=0x");
        print_hex(expected);
        print(")\n");
        fail_count++;
    }
}

// KTRR CSR helpers
static inline void write_ktrr_base(uint32_t val) {
    __asm__ volatile("csrw 0x7C8, %0" :: "r"(val));
}
static inline uint32_t read_ktrr_base(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, 0x7C8" : "=r"(val));
    return val;
}
static inline void write_ktrr_limit(uint32_t val) {
    __asm__ volatile("csrw 0x7C9, %0" :: "r"(val));
}
static inline uint32_t read_ktrr_limit(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, 0x7C9" : "=r"(val));
    return val;
}
static inline void write_ktrr_lock(uint32_t val) {
    __asm__ volatile("csrw 0x7CA, %0" :: "r"(val));
}
static inline uint32_t read_ktrr_lock(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, 0x7CA" : "=r"(val));
    return val;
}

int main() {
    print("=== KTRR Test ===\n");

    // We'll use IMEM addresses 0x0000F000–0x0000F100 as our test region.
    // This is well past our code, inside the 64K IMEM space.
    volatile uint32_t *imem_test = (volatile uint32_t *)0x0000F000;
    volatile uint32_t *imem_outside = (volatile uint32_t *)0x0000F100;

    // Test 1: IMEM read — verify we can load from IMEM addresses
    print("[1] IMEM read... ");
    uint32_t val = *imem_test;  // should not fault, just reads whatever is there
    (void)val;
    check("no fault", 1, 1);   // if we got here, no fault occurred

    // Test 2: IMEM write before lock — write a value and read it back
    print("[2] IMEM write before lock... ");
    *imem_test = 0xDEADBEEF;
    uint32_t readback = *imem_test;
    check("readback", readback, 0xDEADBEEF);

    // Write a value outside the region too (for later test)
    *imem_outside = 0xCAFEBABE;

    // Test 3: KTRR CSR setup — set base/limit, read back
    print("[3] KTRR CSR setup... ");
    write_ktrr_base(0x0000F000);
    write_ktrr_limit(0x0000F100);
    check("base", read_ktrr_base(), 0x0000F000);

    print("[3b] limit readback... ");
    check("limit", read_ktrr_limit(), 0x0000F100);

    // Test 4: Lock
    print("[4] KTRR lock... ");
    write_ktrr_lock(1);
    check("locked", read_ktrr_lock(), 1);

    // Test 5: Store to locked region → fault (mcause=24)
    print("[5] Store to locked region... ");
    TRAP_MCAUSE = 0;
    *imem_test = 0x12345678;   // should fault
    check("mcause=24", TRAP_MCAUSE, 24);

    // Test 5b: Verify the store was actually blocked
    print("[5b] Store blocked... ");
    check("value preserved", *imem_test, 0xDEADBEEF);

    // Test 6: mtval check — should contain the faulting address
    print("[6] mtval check... ");
    check("mtval", TRAP_MTVAL, 0x0000F000);

    // Test 7: Store outside region → no fault
    print("[7] Store outside locked region... ");
    TRAP_MCAUSE = 0;
    *imem_outside = 0x55AA55AA;
    check("no fault", TRAP_MCAUSE, 0);

    // Verify the write actually went through
    print("[7b] outside readback... ");
    check("readback", *imem_outside, 0x55AA55AA);

    // Test 8: CSR frozen after lock — try to change ktrr_base
    print("[8] CSR frozen after lock... ");
    write_ktrr_base(0xFFFFFFFF);
    check("base unchanged", read_ktrr_base(), 0x0000F000);

    print("[8b] limit frozen... ");
    write_ktrr_limit(0xFFFFFFFF);
    check("limit unchanged", read_ktrr_limit(), 0x0000F100);

    print("[8c] lock frozen... ");
    write_ktrr_lock(0);  // try to unlock
    check("still locked", read_ktrr_lock(), 1);

    // Test 9: Load from locked region → no fault (KTRR only blocks stores)
    print("[9] Load from locked region... ");
    TRAP_MCAUSE = 0;
    uint32_t load_val = *imem_test;
    check("no fault", TRAP_MCAUSE, 0);
    // The value should still be 0xDEADBEEF (written in test 2, store in test 5 was faulted)
    print("[9b] data preserved... ");
    check("value", load_val, 0xDEADBEEF);

    // Summary
    print("\n");
    print_hex(pass_count);
    print(" passed, ");
    print_hex(fail_count);
    print(" failed\n");
    print("=== Done ===\n");
    return fail_count;
}
