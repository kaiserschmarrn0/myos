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

__gshared ulong uptime = 0;

void pit_inner() {
    import core.bitop;

    volatileStore(&uptime, volatileLoad(&uptime) + 1);
}

__gshared uint* lapic_eoi_pointer;

void pit_handler() {
    asm {
        naked;

        push RAX;
        push RBX;
        push RCX;
        push RDX;
        push RSI;
        push RDI;
        push RBP;
        push R8;
        push R9;
        push R10;
        push R11;
        push R12;
        push R13;
        push R14;
        push R15;

        call pit_inner;

        mov RAX, lapic_eoi_pointer;
        mov int ptr [RAX], 0;

        pop R15;
        pop R14;
        pop R13;
        pop R12;
        pop R11;
        pop R10;
        pop R9;
        pop R8;
        pop RBP;
        pop RDI;
        pop RSI;
        pop RDX;
        pop RCX;
        pop RBX;
        pop RAX;

        iretq;
    }
}

enum ipi {
    base = 0x40,
    abort = 0x41,
    resched = 0x42,
    abort_exec = 0x43
}

void abort_core() {
    asm {
        naked;

        lock; 
        inc qword ptr[GS:40];

        cli;
    loop1:;
        hlt;
        jmp loop1;
    }
}

alias resched_core = abort_core;
alias abort_exec_core = abort_core;

enum size_t physical_memory_offset = 0xFFFF000000000000;

struct sdt_t {
    align(1):

    ubyte[4] signature;
    uint length;
    ubyte revision;
    ubyte checksum;
    ubyte[6] oem_id;
    ubyte[8] oem_table_id;
    uint oem_revision;
    uint creator_id;
    uint creator_revision;
}

struct madt_t {
    align(1):

    sdt_t sdt;
    uint local_addr;
    uint flags;
    ubyte entries_beginning;
}

madt_t madt;

void write_lapic(uint reg, uint data) {
    import core.bitop;

    ulong base = madt.local_addr + physical_memory_offset;
    volatileStore(cast(uint*)(base + reg), data);
}

void eoi_lapic() {
    write_lapic(0x80, 0);
}

void apic_nmi_handler() {
    eoi_lapic();

    panic("non-maskable apic interrupt.");
}

void master_pic_handler() {
    import io : outb;

    outb(0x20, 0x20);

    panic("spurious master pic interrupt.");
}

void slave_pic_handler() {
    import io : outb;

    outb(0xA0, 0x20);
    outb(0x20, 0x20);

    panic("spurious slave pic interrupt.");
}

void apic_spurious_handler() {
    eoi_lapic();
    
    panic("spurious apic interrupt.");
}