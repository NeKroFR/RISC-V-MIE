#include <stdint.h>

void *memcpy(void *dest, const void *src, uint32_t n) {
    uint8_t *d = dest;
    const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

#define UART_ADDR     (*(volatile uint32_t *)0x40000000)
#define TRAP_MCAUSE   (*(volatile uint32_t *)0x80000100)
#define MMODE_RETURN  (*(volatile uint32_t *)0x80000104)
#define TRAP_MTVAL    (*(volatile uint32_t *)0x80000108)

// PAC instructions live in custom-0 (opcode 0x0B), R-type encoding.
// .insn r opcode, funct3, funct7, rd, rs1, rs2
#define PACIA(rd, rs1, rs2) ".insn r 0x0B, 0, 0, " rd ", " rs1 ", " rs2 "\n"
#define PACDA(rd, rs1, rs2) ".insn r 0x0B, 1, 0, " rd ", " rs1 ", " rs2 "\n"
#define AUTIA(rd, rs1, rs2) ".insn r 0x0B, 0, 1, " rd ", " rs1 ", " rs2 "\n"
#define AUTDA(rd, rs1, rs2) ".insn r 0x0B, 1, 1, " rd ", " rs1 ", " rs2 "\n"

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

void check_ne(const char *name, uint32_t a, uint32_t b) {
    print(name);
    if (a != b) {
        print(" OK\n");
        pass_count++;
    } else {
        print(" FAIL (both=0x");
        print_hex(a);
        print(")\n");
        fail_count++;
    }
}

static inline void write_pac_ia_key(uint32_t k0, uint32_t k1, uint32_t k2, uint32_t k3) {
    __asm__ volatile("csrw 0x7C0, %0" :: "r"(k0));
    __asm__ volatile("csrw 0x7C1, %0" :: "r"(k1));
    __asm__ volatile("csrw 0x7C2, %0" :: "r"(k2));
    __asm__ volatile("csrw 0x7C3, %0" :: "r"(k3));
}

static inline void write_pac_da_key(uint32_t k0, uint32_t k1, uint32_t k2, uint32_t k3) {
    __asm__ volatile("csrw 0x7C4, %0" :: "r"(k0));
    __asm__ volatile("csrw 0x7C5, %0" :: "r"(k1));
    __asm__ volatile("csrw 0x7C6, %0" :: "r"(k2));
    __asm__ volatile("csrw 0x7C7, %0" :: "r"(k3));
}

// We use explicit mv's to pin the operands to a0/a1/a2, since .insn r
// encodes whatever physical registers appear in the instruction.

static uint32_t do_pacia(uint32_t pointer, uint32_t modifier) {
    uint32_t result;
    __asm__ volatile(
        "mv a1, %1\n"
        "mv a2, %2\n"
        ".insn r 0x0B, 0, 0, a0, a1, a2\n"
        "mv %0, a0\n"
        : "=r"(result)
        : "r"(pointer), "r"(modifier)
        : "a0", "a1", "a2"
    );
    return result;
}

static uint32_t do_pacda(uint32_t pointer, uint32_t modifier) {
    uint32_t result;
    __asm__ volatile(
        "mv a1, %1\n"
        "mv a2, %2\n"
        ".insn r 0x0B, 1, 0, a0, a1, a2\n"
        "mv %0, a0\n"
        : "=r"(result)
        : "r"(pointer), "r"(modifier)
        : "a0", "a1", "a2"
    );
    return result;
}

// AUT: recomputes the tag from (rs1, rs2) and traps if it doesn't match rd.
static void do_autia(uint32_t pac_tag, uint32_t pointer, uint32_t modifier) {
    __asm__ volatile(
        "mv a0, %0\n"
        "mv a1, %1\n"
        "mv a2, %2\n"
        ".insn r 0x0B, 0, 1, a0, a1, a2\n"
        :
        : "r"(pac_tag), "r"(pointer), "r"(modifier)
        : "a0", "a1", "a2"
    );
}

static void do_autda(uint32_t pac_tag, uint32_t pointer, uint32_t modifier) {
    __asm__ volatile(
        "mv a0, %0\n"
        "mv a1, %1\n"
        "mv a2, %2\n"
        ".insn r 0x0B, 1, 1, a0, a1, a2\n"
        :
        : "r"(pac_tag), "r"(pointer), "r"(modifier)
        : "a0", "a1", "a2"
    );
}

void __attribute__((noinline)) umode_pacia_test(void) {
    // Sign a pointer from U-mode (keys are hidden but the instruction works)
    __asm__ volatile(
        "li a1, 0xDEADBEEF\n"
        "li a2, 0x42\n"
        ".insn r 0x0B, 0, 0, a0, a1, a2\n"
        "lui t0, 0x80000\n"
        "sw a0, 0x10C(t0)\n"        // stash result for M-mode to read
        "li a0, 1\n"
        "ecall\n"
        ::: "a0", "a1", "a2", "t0", "memory"
    );
}

void __attribute__((noinline)) umode_csr_read_test(void) {
    // Reading a PAC key CSR from U-mode should trap (mcause=2)
    __asm__ volatile(
        "csrr a0, 0x7C0\n"
        "li a0, 1\n"
        "ecall\n"
        ::: "a0"
    );
}

void drop_to_umode(void (*fn)(void)) {
    volatile uint32_t *ret_addr = &MMODE_RETURN;
    __asm__ volatile(
        "la t0, 1f\n"
        "sw t0, 0(%[ret])\n"
        "csrw mepc, %[fn]\n"
        "li t0, 0x1800\n"
        "csrc mstatus, t0\n"        // clear MPP -> U-mode
        "mret\n"
        "1:\n"
        :
        : [fn] "r"(fn), [ret] "r"(ret_addr)
        : "t0", "memory"
    );
}

int main() {
    print("=== PAC Test ===\n");

    // IA key: k0 = 0x0123456789ABCDEF, w0 = 0xFEDCBA9876543210
    write_pac_ia_key(0x89ABCDEF, 0x01234567, 0x76543210, 0xFEDCBA98);

    // 1: signing should produce something
    print("[1] PACIA basic... ");
    uint32_t pac1 = do_pacia(0xDEADBEEF, 0x42);
    check_ne("non-zero", pac1, 0);

    // 2: same inputs -> same tag
    print("[2] PACIA deterministic... ");
    uint32_t pac2 = do_pacia(0xDEADBEEF, 0x42);
    check("same", pac2, pac1);

    // 3: different modifier -> different tag
    print("[3] PACIA diff modifier... ");
    uint32_t pac3 = do_pacia(0xDEADBEEF, 0x43);
    check_ne("diff", pac3, pac1);

    // 4: different key -> different tag
    print("[4] PACIA diff key... ");
    write_pac_ia_key(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    uint32_t pac4 = do_pacia(0xDEADBEEF, 0x42);
    check_ne("diff", pac4, pac1);

    write_pac_ia_key(0x89ABCDEF, 0x01234567, 0x76543210, 0xFEDCBA98);

    // 5: sign then verify -> no trap
    print("[5] AUTIA pass... ");
    uint32_t pac5 = do_pacia(0xCAFEBABE, 0x100);
    TRAP_MCAUSE = 0;
    do_autia(pac5, 0xCAFEBABE, 0x100);
    check("no trap", TRAP_MCAUSE, 0);

    // 6: flip a bit in the tag -> should trap (mcause=18)
    print("[6] AUTIA fail... ");
    TRAP_MCAUSE = 0;
    do_autia(pac5 ^ 1, 0xCAFEBABE, 0x100);
    check("mcause=18", TRAP_MCAUSE, 18);

    // 7: DA key produces different tags than IA key
    print("[7] PACDA/AUTDA... ");
    write_pac_da_key(0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD);
    uint32_t pac_da = do_pacda(0xDEADBEEF, 0x42);
    uint32_t pac_ia = do_pacia(0xDEADBEEF, 0x42);
    check_ne("DA!=IA", pac_da, pac_ia);
    TRAP_MCAUSE = 0;
    do_autda(pac_da, 0xDEADBEEF, 0x42);
    check("AUTDA pass", TRAP_MCAUSE, 0);

    // 8: PAC works from U-mode (keys not readable, but instruction runs)
    print("[8] U-mode PACIA... ");
    __asm__ volatile("csrw 0x3B0, %0" :: "r"(0x00004000));   // pmpaddr0: IMEM top
    __asm__ volatile("csrw 0x3B1, %0" :: "r"(0x20000000));   // pmpaddr1: DMEM base
    __asm__ volatile("csrw 0x3B2, %0" :: "r"(0x20004000));   // pmpaddr2: DMEM top
    __asm__ volatile("csrw 0x3A0, %0" :: "r"(0x000B080D));   // TOR|RX, TOR|---, TOR|RW

    volatile uint32_t *umode_result = (volatile uint32_t *)0x8000010C;
    *umode_result = 0;
    drop_to_umode(umode_pacia_test);
    check_ne("non-zero", *umode_result, 0);

    // 9: U-mode can't read PAC key CSRs (mcause=2)
    print("[9] U-mode key access... ");
    TRAP_MCAUSE = 0;
    drop_to_umode(umode_csr_read_test);
    check("mcause=2", TRAP_MCAUSE, 2);

    print("\n");
    print_hex(pass_count);
    print(" passed, ");
    print_hex(fail_count);
    print(" failed\n");
    print("=== Done ===\n");
    return fail_count;
}
