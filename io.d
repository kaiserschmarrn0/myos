module io;

import core.stdc.stdarg;

import jank;
import lock;

immutable(char[]) hex_table = "0123456789ABCDEF";

shared lock putc_lock;
shared lock puts_lock;
shared lock vprintf_lock;

void outb(ushort port, ubyte val) {
    asm {
        mov DX, port;
        mov AL, val;
        out DX, AL;
    }
}  

void qemu_putc(char c) {
    outb(0xE9, c);
}

void async_putc(char c) {
    static if (1) {
        qemu_putc(c);
    }

    //actual putc
}

void putc(char c) {
    acquire(&putc_lock);
    async_putc(c);
    release(&putc_lock);
}

void async_puts(immutable(char)* str) {
    for (int i = 0; str[i]; i++) {
        async_putc(str[i]);
    }
}

void puts(immutable(char)* str) {
    acquire(&puts_lock);

    async_puts(str);

    release(&puts_lock);
}

void print_ulong(ulong x) {
    if (!x) {
        async_putc('0');
        return;
    }

    int i;
    char[21] buf;

    buf[20] = 0;

    for (i = 19; x; i--) {
        buf[i] = hex_table[x % 10];
        x /= 10;
    }

    i++;
    async_puts(cast(immutable)&buf[i]);
}

void print_hex(ulong x) {
    if (!x) {
        async_puts("0x0");
        return;
    }

    int i;
    char[17] buf;

    buf[16] = 0;

    for (i = 15; x; i--) {
        buf[i] = hex_table[x % 16];
        x /= 16;
    }

    i++;
    async_puts("0x");
    async_puts(cast(immutable)&buf[i]);
}

extern(C) void vprintf(immutable(char)* fmt, va_list args) {
    acquire(&vprintf_lock);

    for (int i = 0; fmt[i]; i++) {
        if (fmt[i] != '%') {
            async_putc(fmt[i]);
            continue;
        }

        if (fmt[++i]) {
            switch (fmt[i]) {
                case 's':
                    immutable(char)* str;
                    va_arg(args, str);
                    async_puts(str);
                    break;
                case 'x':
                    ulong h;
                    va_arg(args, h);
                    print_hex(h);
                    break;
                case 'u':
                    ulong u;
                    va_arg(args, u);
                    print_ulong(u);
                    break;
                default:
                    async_putc('%');
            }
        }
    }

    release(&vprintf_lock);
}

extern(C) void printf(immutable(char)* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
}

extern(C) void panic(immutable(char)* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    printf("panic: ");
    vprintf(fmt, args);
    putc('\n');

    asm {
        cli;
    loop1:;
        hlt;
        jmp loop1;
    }
}