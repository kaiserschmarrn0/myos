module io;

import core.stdc.stdarg;

import jank;
import lock;

alias cstr = immutable(char)*;

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

void putc(char c) {
    acquire(&putc_lock);

    static if (1) {
        qemu_putc(c);
    }

    //actual putc

    release(&putc_lock);
}

void puts(cstr str) {
    acquire(&puts_lock);

    for (int i = 0; str[i]; i++) {
        putc(str[i]);
    }

    release(&puts_lock);
}

void print_ulong(ulong x) {
    int i;
    char[21] buf;

    buf[20] = 0;

    if (!x) {
        putc('0');
        return;
    }

    for (i = 19; x; i--) {
        buf[i] = hex_table[x % 10];
        x /= 10;
    }

    i++;
    puts(cast(immutable)&buf[i]);
}

void print_hex(ulong x) {
    int i;
    char[17] buf;

    buf[16] = 0;

    if (!x) {
        puts("0x0");
        return;
    }

    for (i = 15; x; i--) {
        buf[i] = hex_table[x % 16];
        x /= 16;
    }

    i++;
    puts("0x");
    puts(cast(immutable)&buf[i]);
}

extern(C) void vprintf(cstr fmt, va_list args) {
    acquire(&vprintf_lock);

    for (int i = 0; fmt[i]; i++) {
        if (fmt[i] != '%') {
            putc(fmt[i]);
            continue;
        }

        if (fmt[++i]) {
            switch (fmt[i]) {
                case 's':
                    cstr str;
                    va_arg(args, str);
                    puts(str);
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
                    putc('%');
            }
        }
    }

    release(&vprintf_lock);
}

extern(C) void printf(cstr fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
}

extern(C) void panic(cstr fmt, ...) {
    va_list args;
    va_start(args, fmt);
    printf("panic: ");
    vprintf(fmt, args);

    asm {
        cli;
    loop1:;
        hlt;
        jmp loop1;
    }
}