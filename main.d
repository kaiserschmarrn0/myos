import io;
import lock;

// memory

struct e820_entry {
    ulong base;
    ulong length;
    uint type;
    uint unused;
}

shared(e820_entry)[256] e820_map;

extern(C) void get_e820(shared(e820_entry)*);

enum size_t physical_memory_offset = 0xFFFF800000000000;
enum size_t kernel_physical_memory_offset = 0xFFFFFFFFC0000000;

enum size_t page_size = 4096;
enum size_t page_table_len = 512;

enum uint bmp_realloc_step = 1;
enum size_t mem_base = 0x1000000;
enum size_t bmp_base = mem_base / page_size;

__gshared uint* mem_bmp;
__gshared uint[] initial_bmp = [0xFFFFFF7F];
__gshared uint* tmp_bmp;

__gshared size_t bmp_len = 32;
__gshared size_t cur_ptr = bmp_base;

shared lock pmm_lock;

struct pagemap {
    size_t* pml4;
    lock l;
}

shared pagemap* kernel_pagemap;

extern(C) void main() {

    { // interrupts
        import interrupt;

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

        register_interrupt(0x00, &exception_handler_maker!(0x00, 0).handler, false);
        register_interrupt(0x01, &exception_handler_maker!(0x01, 0).handler, false);
        register_interrupt(0x02, &exception_handler_maker!(0x02, 0).handler, false);
        register_interrupt(0x03, &exception_handler_maker!(0x03, 0).handler, false);
        register_interrupt(0x04, &exception_handler_maker!(0x04, 0).handler, false);
        register_interrupt(0x05, &exception_handler_maker!(0x05, 0).handler, false);
        register_interrupt(0x06, &exception_handler_maker!(0x06, 0).handler, false);
        register_interrupt(0x07, &exception_handler_maker!(0x07, 0).handler, false);
        register_interrupt(0x08, &exception_handler_maker!(0x08, 0).handler, true );
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
        
        // pit
        register_interrupt(0x20, &pit_handler, false);

        // ipis
        register_interrupt(ipi.abort,      &abort_core,      true);
        register_interrupt(ipi.resched,    &resched_core,    true);
        register_interrupt(ipi.abort_exec, &abort_exec_core, true);

        for (int i = 0; i < 16; i++) {
            register_interrupt(0x90 + i, &apic_nmi_handler, true);
        }

        for (int i = 0; i < 8; i++) {
            register_interrupt(0xA0 + i, &master_pic_handler, true);            
        }

        for (int i = 0; i < 8; i++) {
            register_interrupt(0xA8 + i, &slave_pic_handler, true);            
        }

        register_interrupt(0xFF, &apic_spurious_handler, true);

        asm {
            lidt [ptr];
        }

        // go to the bathroom and take a shit NOW
        // NOT YET
        // flush_irqs();
    }

    { // memory

        // i don't think this is well implemented...
        // reallocating the pmm every time it gets bigger...
        // and then having to copy the old one...

        get_e820(e820_map.ptr);

        { //debug
            ulong mem_size = 0;
            foreach (e820_entry entry; e820_map) {
                if (!entry.type) {
                    break;
                }

                immutable(char)* e820_type(uint type) {
                    switch (type) {
                        case 1: return "usable";
                        case 2: return "reserved";
                        case 3: return "acpi-reclaim";
                        case 4: return "acpi-nvs";
                        case 5: return "bad";
                        default: return "???";
                    }
                }

                printf("e820: %x ... %x : %x %s\n", entry.base, entry.base + entry.length, entry.length, e820_type(entry.type));

                if (entry.type == 1) {
                    mem_size += entry.length;
                }
            }

            printf("e820: total usable memory: %u mb\n", mem_size / 1024 / 1024);
        }

        void set_bit(size_t i) {
            i -= bmp_base;

            asm {
                mov RAX, bmp_base;
                mov RBX, i;
                bts [RAX], RBX;
            }
        }

        void unset_bit(size_t i) {
            i -= bmp_base;

            asm {
                mov RAX, bmp_base;
                mov RBX, i;
                btr [RAX], RBX;
            }
        }

        void* pmm_alloc(size_t page_count) {
            acquire(&pmm_lock);

            void* ret = null;
            size_t cur_page_count = page_count;

            for (int i = 0; i < bmp_len; i++) {
                if (cur_ptr == bmp_base + bmp_len) {
                    cur_ptr = bmp_base;
                    cur_page_count = page_count;
                }

                size_t off = cur_ptr - bmp_base;
                cur_ptr++;    
                
                bool bit = false; // shoudln't need to set this
                
                asm {
                    mov RAX, bmp_base;
                    mov RBX, off;
                    bt [RAX], RBX;
                    setc bit;
                }

                if (!bit) {
                    cur_page_count--;
                    if (!cur_page_count) {
                        size_t start = cur_ptr - page_count;

                        for (int j = 0; j < page_count; j++) {
                            set_bit(j);
                        }

                        ret = cast(void*)(start * page_size);

                        break;
                    }
                } else {
                    cur_page_count = page_count;
                }
            }

            release(&pmm_lock);
            return ret;
        }

        void* pmm_alloc_z(size_t page_count) {
            ulong* ptr = cast(ulong*)(cast(ulong)pmm_alloc(page_count) + physical_memory_offset);
                    
            foreach (size_t i; 0..bmp_realloc_step * page_size / uint.sizeof) {
                ptr[i] = 0;
            }

            return cast(void*)ptr;
        }

        void pmm_free(void *bmp, size_t page_count) {
            acquire(&pmm_lock);
            
            size_t start = cast(size_t)bmp / page_size;

            foreach (size_t i; start..start + page_count) {
                unset_bit(i);
            }

            release(&pmm_lock);
        }

        mem_bmp = &initial_bmp[0];
        tmp_bmp = cast(uint*)pmm_alloc_z(bmp_realloc_step);
    
        assert(tmp_bmp);

        tmp_bmp = cast(uint*)(cast(ulong)tmp_bmp + physical_memory_offset);

        foreach(i; 0..bmp_realloc_step * page_size / uint.sizeof) {
            tmp_bmp[i] = 0xFFFFFFFF;
        }
        
        mem_bmp = tmp_bmp;

        bmp_len = ((page_size / uint.sizeof) * 32) * bmp_realloc_step;

        for (uint i = 0; e820_map[i].type; i++) {
            size_t aligned_base;
            if (e820_map[i].base % page_size) {
                aligned_base = e820_map[i].base + (page_size - (e820_map[i].base % page_size));
            } else {
                aligned_base = e820_map[i].base;
            }

            size_t aligned_length = (e820_map[i].length / page_size) * page_size;

            if ((e820_map[i].base % page_size) && aligned_length) {
                aligned_length -= page_size;
            }

            for (size_t j = 0; j * page_size < aligned_length; j++) {
                size_t addr = aligned_base + j * page_size;

                size_t page = addr / page_size;

                if (addr < (mem_base + page_size)) {
                    continue;
                }

                if (addr >= (mem_base + bmp_len * page_size)) {
                    size_t cur_bmp_size = ((bmp_len / 32) * uint.sizeof) / page_size;
                    size_t new_bmp_size = cur_bmp_size + bmp_realloc_step;

                    tmp_bmp = cast(uint*)pmm_alloc(new_bmp_size);
                    if (!tmp_bmp) {
                        panic("pmm_alloc failure.");
                    }

                    tmp_bmp = cast(uint*)(cast(size_t)tmp_bmp + physical_memory_offset);

                    const size_t len = cur_bmp_size * page_size / uint.sizeof;
                    foreach (size_t k; 0..len) {
                        tmp_bmp[k] = mem_bmp[k];
                    }

                    foreach(size_t k; len..new_bmp_size * page_size / uint.sizeof) {
                        tmp_bmp[k] = 0xFFFFFFFF;
                    }

                    bmp_len += ((page_size / uint.sizeof) * 32) * bmp_realloc_step;
                    uint* old_bmp = cast(uint*)(cast(ulong)mem_bmp - physical_memory_offset);

                    mem_bmp = tmp_bmp;
                    pmm_free(old_bmp, cur_bmp_size);
                }
            }
        }

        /*mem_bmp = &initial_bmp[0];
        tmp_bmp = cast(uint*)pmm_alloc_z(bmp_realloc_step);

        assert(tmp_bmp);

        tmp_bmp = cast(uint*)(cast(ulong)tmp_bmp + physical_memory_offset);

        foreach (size_t i; 0..bmp_realloc_step * page_size / uint.sizeof) {
            tmp_bmp[i] = 0xFFFFFFFF;
        }

        mem_bmp = tmp_bmp;

        bmp_len = ((page_size / uint.sizeof) * 32) * bmp_realloc_step;

        // For each region specified by the e820, iterate over each page which
        // fits in that region and if the region type indicates the area itself
        // is usable, write that page as free in the bitmap. Otherwise, mark the
        // page as used.
        for (auto i = 0; e820_map[i].type; i++) {
            size_t alignedBase;

            if (e820_map[i].base % page_size) {
                alignedBase = e820_map[i].base +
                            (page_size - (e820_map[i].base % page_size));
            } else alignedBase = e820_map[i].base;

            size_t alignedLength = (e820_map[i].length / page_size) * page_size;

            if ((e820_map[i].base % page_size) && alignedLength) {
                alignedLength -= page_size;
            }

            for (auto j = 0; j * page_size < alignedLength; j++) {
                size_t addr = alignedBase + j * page_size;

                size_t page = addr / page_size;

                if (addr < mem_base + page_size) {
                    continue;
                }

                // Reallocate bitmap
                if (addr >= (mem_base + bmp_len * page_size)) {
                    size_t currentBitmapSizeInPages = ((bmp_len / 32) *
                                                    uint.sizeof) / page_size;
                    size_t newBitmapSizeInPages = currentBitmapSizeInPages +
                                                bmp_realloc_step;
                    tmp_bmp = cast(uint*)pmm_alloc_z(newBitmapSizeInPages);

                    assert(tmp_bmp);

                    tmp_bmp = cast(uint*)(cast(size_t)tmp_bmp +
                                physical_memory_offset);

                    // Copy over previous bitmap
                    foreach (k;
                            0..currentBitmapSizeInPages * page_size / uint.sizeof) {
                        tmp_bmp[k] = mem_bmp[k];
                    }

                    // Fill in the rest
                    for (auto k = (currentBitmapSizeInPages * page_size) /
                        uint.sizeof;
                        k < (newBitmapSizeInPages * page_size) / uint.sizeof; k++) {
                        tmp_bmp[k] = 0xFFFFFFFF;
                    }

                    bmp_len += ((page_size / uint.sizeof) * 32) *
                                    bmp_realloc_step;
                    auto oldBitmap = cast(uint*)(cast(ulong)mem_bmp -
                                    physical_memory_offset);
                    mem_bmp = tmp_bmp;
                    pmm_free(oldBitmap, currentBitmapSizeInPages);
                }

                unset_bit(page);
            }
        }*/
        
        struct alloc_md {
            ulong pages;
            ulong size;
        }

        void* alloc(size_t size) {
            size_t pageCount = (size + page_size - 1) / page_size;

            auto ptr = cast(ubyte*)pmm_alloc_z(pageCount + 1);

            if (!ptr) {
                return null;
            }

            ptr += physical_memory_offset;

            auto metadata = cast(alloc_md*)ptr;
            ptr          += page_size;

            metadata.pages = pageCount;
            metadata.size  = size;

            return cast(void*)ptr;
        }

        /*void* alloc(size_t size) {
            size_t page_count = (size + page_size - 1) / page_size;

            auto ptr = cast(ubyte*)pmm_alloc_z(page_count + 1);

            if (!ptr) {
                return null;
            }

            ptr += physical_memory_offset;

            auto md = cast(alloc_md*)ptr;
            ptr += page_size;

            //md.pages = page_count;
            //md.size = size;

            return cast(void*)ptr;
        }*/

        void free(void* ptr) {
            alloc_md* md = cast(alloc_md*)(cast(ulong)ptr - page_size);
            void* md_phys = cast(void*)(cast(ulong)md - physical_memory_offset);
        
            pmm_free(md_phys, md.pages + 1);
        }

        kernel_pagemap = cast(shared) cast(pagemap*)alloc(pagemap.sizeof);
        assert(kernel_pagemap);

        kernel_pagemap.pml4 = cast(shared) cast(size_t*)pmm_alloc_z(1);

        if (!kernel_pagemap.pml4) {
            panic("failed to allocate pagemap.\n");
            // free(kernel_pagemap); doesn't matter
        }

        kernel_pagemap.pml4 = cast(shared) cast(size_t*)(cast(size_t)kernel_pagemap.pml4 + physical_memory_offset);

        bool map_page(shared pagemap* pm, size_t vaddr, size_t paddr, size_t flags) {
            acquire(&pm.l);
            /*scope(exit) { thank you d
                release(&pm.l);
            }*/

            size_t pml4_entry = (vaddr & (cast(size_t)0x1FF << 39)) >> 39;
            size_t pdpt_entry = (vaddr & (cast(size_t)0x1FF << 30)) >> 30;
            size_t pd_entry = (vaddr & (cast(size_t)0x1FF << 21)) >> 21;
            size_t pt_entry = (vaddr & (cast(size_t)0x1FF << 12)) >> 12;

            size_t* pdpt;
            size_t* pd;
            size_t* pt;
            
            if (pm.pml4[pml4_entry] & 0x1) {
                pdpt = cast(size_t*)((pm.pml4[pml4_entry] & 0xFFFFFFFFFFFFF000) + physical_memory_offset);
            } else {
                pdpt = cast(size_t*)(cast(size_t)pmm_alloc_z(1) + physical_memory_offset);

                if (cast(size_t)pdpt == physical_memory_offset) {
                    return false;
                }

                pm.pml4[pml4_entry] = cast(size_t)(cast(size_t)pdpt - physical_memory_offset) | 0b111;
            }

            // size_t* pd; really should be here but d sucks
            if (pdpt[pdpt_entry] & 0x1) {
                pd = cast(size_t*)((pdpt[pdpt_entry] & 0xFFFFFFFFFFFFF000) + physical_memory_offset);
            } else {
                pd = cast(size_t*)(cast(size_t)pmm_alloc_z(1) + physical_memory_offset);

                if (cast(size_t)pd == physical_memory_offset) {
                    goto fail2;
                }

                pdpt[pdpt_entry] = cast(size_t)(cast(size_t)pd - physical_memory_offset) | 0b111;
            }

            // size_t* pt; really should be here but d sucks
            if (pd[pd_entry] & 0x1) {
                pt = cast(size_t*)((pd[pd_entry] & 0xFFFFFFFFFFFFF000) + physical_memory_offset);
            } else {
                pt = cast(size_t*)(cast(size_t)pmm_alloc_z(1) + physical_memory_offset);

                if (cast(size_t)pt == physical_memory_offset) {
                    goto fail3;
                }

                pd[pd_entry] = cast(size_t)(cast(size_t)pt - physical_memory_offset) | 0b111;
            }

            pt[pt_entry] = cast(size_t)(paddr | flags);

            release(&pm.l); 
            return true;

            fail3:
            for (size_t i = 0; i < page_table_len; i++) {
                if (pd[i] & 0x1) {
                    release(&pm.l); 
                    return false;
                }
            }

            pmm_free(cast(void*)pd - physical_memory_offset, 1);

            fail2:
            for (size_t i = 0; i < page_table_len; i++) {
                if (pdpt[i] & 0x1) {
                    release(&pm.l); 
                    return false;
                }
            }

            pmm_free(cast(void*)pdpt - physical_memory_offset, 1);

            release(&pm.l);     
            return false;
        }

        // first 4 gigs
        foreach(size_t i; 0..0x2000000 / page_size) {
            //ulong addr = i * page_size;

            //map_page(kernel_pagemap, addr, addr, 0x03);
            //map_page(kernel_pagemap, addr + physical_memory_offset, addr, 0x03);
            //map_page(kernel_pagemap, addr + kernel_physical_memory_offset, addr, 0x03);
        }
    }

    assert(1 == 2);
}