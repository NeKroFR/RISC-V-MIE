#include <stddef.h>

#define UART_ADDR (*(volatile char *)0x40000000)
#define UART_LSR  (*(volatile char *)0x40000004)
#define LSR_RX_READY 0x01
#define LSR_TX_IDLE  0x20

void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    while (n--) {
        *p++ = (unsigned char)c;
    }
    return s;
}

void print(const char *str) {
    while (*str) {
        UART_ADDR = (unsigned char)*str++;
    }
}

int input(char *buf, int buf_size) {
    int i = 0;
    unsigned char c;

    while (1) {
        if (!(UART_LSR & LSR_RX_READY))
            continue;

        c = UART_ADDR;

        // Handle Backspace
        if (c == 0x7f || c == 0x08) {
            if (i > 0) {
                i--;
                print("\b \b");
            }
            continue;
        }

        char echo_str[2] = {c, '\0'};
        print(echo_str);
        if (c == '\n' || c == '\r') {
            buf[i] = '\0';
            return i;
        }

        if (i < buf_size - 1) {
            buf[i++] = c;
        } else {
            buf[i] = '\0';
            print("\n[Buffer Full]\n");
            return i;
        }
    }
}

int main() {
    char buf[256];

    while (1) {
        memset(buf, 0, sizeof(buf));
        print("$ ");
        input(buf, sizeof(buf));
        
        if (buf[0] != '\0') {
            print(buf);
            print("\n");
        }
        if (buf[0] == 'q' && buf[1] == '\0')
            break;
    }
    return 0;
}
