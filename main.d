import io;

// memory

struct e820_entry {
    ulong base;
    ulong length;
    uint type;
    uint unused;
}

shared(e820_entry)[256] e820_map;

extern(C) void get_e820(shared(e820_entry)*);

extern(C) void main() {
    {
        import interrupt;

        //interrupts
        
        asm {
            cli;
        }

        struct idt_ptr {
            align(1):
            
            ushort size;
            ulong off;
        }

        idt_ptr ptr = {
            size: idt.sizeof,
            off: cast(ulong)&idt
        };

        void register_interrupt(uint i, void function() handler, bool ist) {
            ulong addr = cast(ulong)handler;

            idt[i].offset_low = cast(ushort)addr;
            idt[i].selector = 0x08;
            idt[i].ist = ist ? 1 : 0;
            idt[i].flags = 0x8E;
            idt[i].offset_mid = cast(ushort)(addr >> 16);
            idt[i].offset_high = cast(uint)(addr >> 32);
            idt[i].reserved = 0;
        }
        
        for (uint i = 0; i < idt.length; i++) {
            register_interrupt(i, &default_interrupt_handler, false);
        }

        //exception_handler!(0, 0).handler();

        //void function() t = &exception_handler!(0, 0).handler;

        register_interrupt(0x00, &exception_handler_maker!(0x00, 0).handler, false);
        register_interrupt(0x01, &exception_handler_maker!(0x01, 0).handler, false);
        register_interrupt(0x02, &exception_handler_maker!(0x02, 0).handler, false);
        register_interrupt(0x03, &exception_handler_maker!(0x03, 0).handler, false);
        register_interrupt(0x04, &exception_handler_maker!(0x04, 0).handler, false);
        register_interrupt(0x05, &exception_handler_maker!(0x05, 0).handler, false);
        register_interrupt(0x06, &exception_handler_maker!(0x06, 0).handler, false);
        register_interrupt(0x07, &exception_handler_maker!(0x07, 0).handler, false);
        register_interrupt(0x08, &exception_handler_maker!(0x08, 0).handler, false);
        register_interrupt(0x09, &exception_handler_maker!(0x09, 0).handler, false);
        register_interrupt(0x0A, &exception_handler_maker!(0x0A, 1).handler, false);
        register_interrupt(0x0B, &exception_handler_maker!(0x0B, 1).handler, false);
        register_interrupt(0x0C, &exception_handler_maker!(0x0C, 1).handler, false);
        register_interrupt(0x0D, &exception_handler_maker!(0x0D, 1).handler, false);
        register_interrupt(0x0E, &exception_handler_maker!(0x0E, 1).handler, false);
        // nothing to see here dumbass
        register_interrupt(0x10, &exception_handler_maker!(0x10, 0).handler, false);
        register_interrupt(0x11, &exception_handler_maker!(0x11, 0).handler, false);
        register_interrupt(0x12, &exception_handler_maker!(0x12, 0).handler, false);
        register_interrupt(0x13, &exception_handler_maker!(0x13, 0).handler, false);
        register_interrupt(0x14, &exception_handler_maker!(0x14, 0).handler, false);
        // see above
        register_interrupt(0x1E, &exception_handler_maker!(0x1E, 0).handler, false);
        // ...
        //register_interrupt(0x20, &exception_handler_maker!(0x20, 0).handler, false);
        
        asm {
            lidt [ptr];
        }

        //doesn't work probably depends on other shit
        //flush_irqs();

        exception_entry(0, true);
    }

    {
        //memory
        
        //doesn't work probably messed up real routines
        //get_e820(e820_map.ptr);
    }

    assert(1 == 2);
}