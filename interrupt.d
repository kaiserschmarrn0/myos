module interrupt;

import io;

struct idt_desc {
    ushort offset_low;
    ushort selector;
    ubyte ist;
    ubyte flags;
    ushort offset_mid;
    uint offset_high;
    uint reserved;
}

struct exception_stack_state {
    ulong error;
    ulong rip;
    ulong cs;
    ulong rflags;
    ulong rsp;
    ulong ss;
}

extern(C) void flush_irqs();

shared(idt_desc)[256] idt;

private immutable(immutable(char)*[]) exception_names = [
    "(#ud) division by 0",
    "(#de) debug",
    "(nmi) non maskable interrupt",
    "(#bp) breakpoint",
    "(#of) overflow",
    "(#br) bound range",
    "(#ud) invalid opcode",
    "(#nm) device not available",
    "(#df) double fault",
    "(cso) coprocessor segment overrun",
    "(#ts) invalid tss",
    "(#np) segmant not present",
    "(#ss) stack-segment fault",
    "(#gp) general protection fault",
    "(#pf) page fault",
    "(15) reserved",
    "(#mf) x87 floating point",
    "(#ac) alignment check",
    "(#mc) machine check",
    "(#xf) simd fp exception",
    "(#vr) virtualization exception",
    "(0x15) reserved",
    "(0x16) reserved",
    "(0x17) reserved",
    "(0x18) reserved",
    "(0x19) reserved",
    "(0x1a) reserved",
    "(0x1b) reserved",
    "(0x1c) reserved",
    "(0x1d) reserved",
    "(#sx) security exception",
    "(0x1f) reserved"
];

pragma(inline, true) extern(C) void exception_inner(exception_stack_state* stack, uint exception) {
    printf("ss:     %x\n", stack.ss);
    printf("rsp:    %x\n", stack.rsp);
    printf("rflags: %x\n", stack.rflags);
    printf("cs:     %x\n", stack.cs);
    printf("rip:    %x\n", stack.rip);
    printf("error:  %x\n", stack.error);

    immutable(char)* space = stack.cs & 0b111 ? "user" : "kernel";

    panic("%s in %s", exception_names[exception], space);
}

extern(C) void exception_entry(uint exception_number, bool has_error_code) {
    asm {
        naked;

        pop RAX;

        test SIL, SIL;
        jnz end;
        push 0;

    end:;
        mov ESI, EDI;
        mov RDI, RSP;
        call exception_inner;
    }
}

void default_interrupt_handler() {
    panic("unhandled interrupt.");
}

template exception_handler_maker(ulong exception_number, ulong has_error_code) {
    void handler() {
        asm {
            naked;

            mov RDI, exception_number;
            mov RSI, has_error_code;
            call exception_entry;
        }
    }
}