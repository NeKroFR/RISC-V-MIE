#include <stdint.h>

#define UART_ADDR     (*(volatile uint32_t *)0x40000000)
#define TRAP_MCAUSE   (*(volatile uint32_t *)0x80000100)
#define MMODE_RETURN  (*(volatile uint32_t *)0x80000104)

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

// User-mode code: entry point for code running in U-mode
// Located at a known label for the assembly to reference
void __attribute__((noinline)) umode_ecall_test(void) {
    // This runs in U-mode. ECALL should cause trap with mcause=8.
    __asm__ volatile("ecall");
    // We're back in U-mode after trap handler returns

    // Exit back to M-mode: a0=1 signals "exit" to trap handler
    __asm__ volatile("li a0, 1; ecall");
    // Should not reach here — trap handler redirects to M-mode
}

void __attribute__((noinline)) umode_csr_test(void) {
    // This runs in U-mode. CSR access should trap as illegal instruction.
    __asm__ volatile("csrr t0, mstatus");
    // After trap handler returns (advanced past the illegal instr)

    // Exit back to M-mode
    __asm__ volatile("li a0, 1; ecall");
}

void __attribute__((noinline)) umode_mret_test(void) {
    // This runs in U-mode. MRET should trap as illegal instruction.
    __asm__ volatile("mret");
    // After trap handler returns (advanced past the illegal instr)

    // Exit back to M-mode
    __asm__ volatile("li a0, 1; ecall");
}

// Drop to U-mode, execute fn, return to M-mode when fn does exit ecall
void drop_to_umode(void (*fn)(void)) {
    // Save our return point for the trap handler
    volatile uint32_t *ret_addr = &MMODE_RETURN;

    // Use inline asm to:
    // 1. Save the "after mret" address to MMODE_RETURN
    // 2. Set mepc = fn
    // 3. Clear MPP in mstatus (MPP=U=00)
    // 4. MRET → jumps to fn in U-mode
    // When fn does ecall with a0=1, trap handler sets mepc=MMODE_RETURN, MPP=M, mret
    __asm__ volatile(
        "la t0, 1f\n"            // t0 = return address (label 1)
        "sw t0, 0(%[ret])\n"     // MMODE_RETURN = return addr
        "csrw mepc, %[fn]\n"     // mepc = fn
        "li t0, 0x1800\n"        // MPP mask (bits 12:11)
        "csrc mstatus, t0\n"     // Clear MPP → U-mode
        "mret\n"                 // Jump to fn in U-mode
        "1:\n"                   // Return here from trap handler
        :
        : [fn] "r"(fn), [ret] "r"(ret_addr)
        : "t0", "memory"
    );
}

int main() {
    print("=== Privilege Test ===\n");

    // Test 1: M-mode ECALL gives mcause=11
    print("[1] M-mode ECALL... ");
    __asm__ volatile("ecall");
    check("mcause=11", TRAP_MCAUSE, 11);

    // Test 2: Drop to U-mode, ECALL gives mcause=8
    print("[2] U-mode ECALL... ");
    TRAP_MCAUSE = 0; // Clear
    drop_to_umode(umode_ecall_test);
    check("mcause=8", TRAP_MCAUSE, 8);

    // Test 3: U-mode CSR access → illegal instruction (mcause=2)
    print("[3] U-mode CSR access... ");
    TRAP_MCAUSE = 0;
    drop_to_umode(umode_csr_test);
    check("mcause=2", TRAP_MCAUSE, 2);

    // Test 4: U-mode MRET → illegal instruction (mcause=2)
    print("[4] U-mode MRET... ");
    TRAP_MCAUSE = 0;
    drop_to_umode(umode_mret_test);
    check("mcause=2", TRAP_MCAUSE, 2);

    // Test 5: Verify we're back in M-mode (CSR access should work)
    print("[5] Back in M-mode... ");
    uint32_t mtvec_val;
    __asm__ volatile("csrr %0, mtvec" : "=r"(mtvec_val));
    check("mtvec=0x100", mtvec_val, 0x100);

    // Summary
    print("\n");
    print_hex(pass_count);
    print(" passed, ");
    print_hex(fail_count);
    print(" failed\n");
    print("=== Done ===\n");
    return fail_count;
}
