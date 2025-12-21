#include <stddef.h>

void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    while (n--) {
        *p++ = (unsigned char)c;
    }
    return s;
}

void print(const char *str) {
    while (*str) {
        *(volatile unsigned char *)0x80000000 = *str++;
    }
}

int input(char *buf, int buf_size) {
    int i = 0;
    unsigned char c;

    while (1) {
        c = *(volatile unsigned char *)0x80000000;
        if (!c) {
            continue;
        }

        if (c == '\n' || c == '\r') {
            buf[i] = '\0';
            return i;
        }

        if (i < buf_size - 1) {
            buf[i++] = c;
        } else {
            buf[i] = '\0';
            print("\r\n");
            return i;
        }
    }
}

int main() {
    char buf[256] = {0};

    while (1) {
        print("$ ");
        input(buf, sizeof(buf));
        print(buf);
        print("\n");
        if (buf[0] == 'q' && buf[1] == '\0')
            break;
    }
    return 0;
}
