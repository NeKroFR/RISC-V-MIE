#include <stdint.h>

#define UART_ADDR     (*(volatile uint32_t *)0x40000000)
#define TRAP_MCAUSE   (*(volatile uint32_t *)0x80000100)
#define MMODE_RETURN  (*(volatile uint32_t *)0x80000104)
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

static inline void write_pmpcfg0(uint32_t val) {
    __asm__ volatile("csrw 0x3A0, %0" :: "r"(val));
}

static inline uint32_t read_pmpcfg0(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, 0x3A0" : "=r"(val));
    return val;
}

static inline void write_pmpaddr0(uint32_t val) {
    __asm__ volatile("csrw 0x3B0, %0" :: "r"(val));
}
static inline void write_pmpaddr1(uint32_t val) {
    __asm__ volatile("csrw 0x3B1, %0" :: "r"(val));
}
static inline void write_pmpaddr2(uint32_t val) {
    __asm__ volatile("csrw 0x3B2, %0" :: "r"(val));
}
static inline void write_pmpaddr3(uint32_t val) {
    __asm__ volatile("csrw 0x3B3, %0" :: "r"(val));
}

static inline uint32_t read_pmpaddr0(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, 0x3B0" : "=r"(val));
    return val;
}

static void pmp_clear(void) {
    write_pmpcfg0(0);
    write_pmpaddr0(0);
    write_pmpaddr1(0);
    write_pmpaddr2(0);
    write_pmpaddr3(0);
}

void __attribute__((noinline)) umode_load_test(void) {
    volatile uint32_t *p = (volatile uint32_t *)0x80000000;
    (void)*p;
    __asm__ volatile("li a0, 1; ecall");
}

void __attribute__((noinline)) umode_store_test(void) {
    volatile uint32_t *p = (volatile uint32_t *)0x80000200;
    *p = 0xDEADBEEF;
    __asm__ volatile("li a0, 1; ecall");
}

// naked because gcc treats *(NULL) as UB and kills the exit ecall
void __attribute__((noinline, naked)) umode_bad_store_test(void) {
    __asm__ volatile(
        "sw zero, 0(zero)\n"
        "li a0, 1\n"
        "ecall\n"
        ::: "a0", "memory"
    );
}

void __attribute__((noinline)) umode_bad_load_test(void) {
    volatile uint32_t *p = (volatile uint32_t *)0x50000000;
    (void)*p;
    __asm__ volatile("li a0, 1; ecall");
}

void __attribute__((noinline)) umode_nop_exit(void) {
    __asm__ volatile("li a0, 1; ecall");
}

void drop_to_umode(void (*fn)(void)) {
    volatile uint32_t *ret_addr = &MMODE_RETURN;
    __asm__ volatile(
        "la t0, 1f\n"
        "sw t0, 0(%[ret])\n"
        "csrw mepc, %[fn]\n"
        "li t0, 0x1800\n"
        "csrc mstatus, t0\n"
        "mret\n"
        "1:\n"
        :
        : [fn] "r"(fn), [ret] "r"(ret_addr)
        : "t0", "memory"
    );
}

int main() {
    print("=== PMP Test ===\n");

    // Test 1: TOR — IMEM(RX) + gap(---) + DMEM(RW), U-mode load should work
    print("[1] TOR basic (U-mode load)... ");
    pmp_clear();
    write_pmpaddr0(0x00004000);   // IMEM top  (0x10000 >> 2)
    write_pmpaddr1(0x20000000);   // DMEM base (0x80000000 >> 2)
    write_pmpaddr2(0x20004000);   // DMEM top  (0x80010000 >> 2)
    write_pmpcfg0(0x000B080D);    // entry0=TOR|RX, entry1=TOR|---, entry2=TOR|RW

    TRAP_MCAUSE = 0;
    drop_to_umode(umode_load_test);
    check("no fault", TRAP_MCAUSE, 0);

    // Test 2: TOR deny — U-mode store to IMEM (RX only) → mcause=7
    print("[2] TOR deny (U-mode bad store)... ");
    TRAP_MCAUSE = 0;
    drop_to_umode(umode_bad_store_test);
    check("mcause=7", TRAP_MCAUSE, 7);

    // Test 3: NAPOT — 64K DMEM region, U-mode store should work
    // NAPOT encoding: (0x80000000>>2) | (0x10000>>3 - 1) = 0x20001FFF
    print("[3] NAPOT (U-mode store)... ");
    pmp_clear();
    write_pmpaddr0(0x00004000);   // IMEM TOR
    write_pmpaddr1(0x20001FFF);   // DMEM NAPOT 64K
    write_pmpcfg0(0x00001B0D);    // entry0=TOR|RX, entry1=NAPOT|RW

    TRAP_MCAUSE = 0;
    drop_to_umode(umode_store_test);
    check("no fault", TRAP_MCAUSE, 0);

    // Test 4: No PMP match for 0x50000000 → U-mode load fault (mcause=5)
    print("[4] No match deny (U-mode load)... ");
    TRAP_MCAUSE = 0;
    drop_to_umode(umode_bad_load_test);
    check("mcause=5", TRAP_MCAUSE, 5);

    // Test 5: Lock bit — NA4 locks 0x80002000 as R-only, M-mode store should fault
    // NA4 at entry1 matches before the NAPOT at entry2
    print("[5] Lock bit (M-mode store fault)... ");
    pmp_clear();
    write_pmpaddr0(0x00004000);   // IMEM TOR
    write_pmpaddr1(0x20000800);   // NA4 at 0x80002000
    write_pmpaddr2(0x20001FFF);   // DMEM NAPOT 64K
    write_pmpcfg0(0x001B910D);    // entry0=TOR|RX, entry1=L|NA4|R, entry2=NAPOT|RW

    TRAP_MCAUSE = 0;
    volatile uint32_t *locked_addr = (volatile uint32_t *)0x80002000;
    *locked_addr = 0x12345678;    // should fault
    check("mcause=7", TRAP_MCAUSE, 7);

    // Test 6: mtval — load fault at 0x50000000, check mtval has the address
    // Entry 1 is still locked from test 5 but only covers 4 bytes, doesn't matter
    print("[6] mtval check... ");
    write_pmpaddr0(0x00004000);
    write_pmpaddr2(0x20001FFF);
    write_pmpaddr3(0);
    write_pmpcfg0(0x001B910D);    // entry1 byte won't change (locked)

    TRAP_MCAUSE = 0;
    TRAP_MTVAL = 0;
    drop_to_umode(umode_bad_load_test);
    check("mtval=0x50000000", TRAP_MTVAL, 0x50000000);

    // Test 7: Instruction fetch fault — only DMEM has PMP coverage, no X for IMEM
    // U-mode fetch immediately faults (mcause=1), trap handler exits to M-mode
    print("[7] Instr fetch fault... ");
    write_pmpaddr0(0x20001FFF);   // move entry0 to NAPOT DMEM
    write_pmpaddr2(0);
    write_pmpcfg0(0x0000911B);    // entry0=NAPOT|RW, entry1=locked, rest OFF

    TRAP_MCAUSE = 0;
    drop_to_umode(umode_nop_exit);
    check("mcause=1", TRAP_MCAUSE, 1);

    // Test 8: CSR read-back
    print("[8] PMP CSR read-back... ");
    write_pmpaddr0(0xDEADBEEF);
    check("pmpaddr0", read_pmpaddr0(), 0xDEADBEEF);

    // Summary
    print("\n");
    print_hex(pass_count);
    print(" passed, ");
    print_hex(fail_count);
    print(" failed\n");
    print("=== Done ===\n");
    return fail_count;
}
