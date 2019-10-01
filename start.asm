%define kernel_physical_offset 0xFFFFFFFFC0000000

[bits 32]

section .multiboot
align 4
    dd 0x1BADB002
    dd 0
    dd -0x1BADB002

section .rodata

no_cpuid_msg: db "no cpuid", 0
no_long_mode_msg: db "no long mode", 0

[bits 64]

align 16
gdt_pointer_lower_half:
    dw gdt_pointer.end - gdt_pointer.start ; size
    dd gdt_pointer.start - kernel_physical_offset ; start

align 16
gdt_pointer:
    dw .start - .start - 1
    dq .start

align 16
.start:
.null_descriptor:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 00000000b
    db 00000000b
    db 0x00

.kernel_code_64:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 10011010b
    db 00100000b
    db 0x00

.kernel_data:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 10010010b
    db 00000000b
    db 0x00

.user_data_64:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 11110010b
    db 00000000b
    db 0x00

.user_code_64:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 11110010b
    db 00100000b
    db 0x00

.unreal_code:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 10001111b
    db 0x00

.tss:
    dw 104
.tss_low:
    dw 0
.tss_mid:
    db 0
.tss_flags1:
    db 10001001b
.tss_flags2:
    db 00000000b
.tss_high:
    db 0
.tss_upper32:
    dd 0
.tss_reserved:
    dd 0
.end:

[bits 32]

section .bss
align 4096

pagemap:
.pml4:
    resb 4096
.pdpt_low:
    resb 4096
.pdpt_high:
    resb 4096
.pd:
    resb 4096
.pt:
    resb 4096 * 16 ; 16 page tables
.end:

section .text

global early_error:function (early_error.end - early_error)
early_error:
    pusha
    mov edi, 0xB8000

.loop:
    lodsb
    test al, al
    jz .out
    stosb
    inc edi
    jmp .loop

.out:
    popa
    cli

.hang:
    hlt
    jmp .hang
    ret
.end:

global start:function (start.end - start)
start:
    extern main

    ; setup stack pointer
    mov esp, 0xEFFFF0

    ; setup cpuid

    pushfd
    pop eax

    mov ecx, eax

    ; flip id bit
    xor eax, 1 << 21

    push eax
    popfd

    pushfd
    pop eax
    
    push ecx
    popfd

    xor eax, ecx
    jz .no_cpuid
    
    jmp .cpuid_done

.no_cpuid:
    mov esi, no_cpuid_msg - kernel_physical_offset
    call early_error
    ; .error_msg db "CPUID not supported.", 0

.cpuid_done:
    ; check long mode

    ; check extended functions
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no_long_mode

    ; check long mode
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz .no_long_mode

    ; set long mode bit in EFER MSR
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    jmp .long_mode_done

.no_long_mode:
    mov esi, no_long_mode_msg - kernel_physical_offset
    call early_error

.long_mode_done:
    ; paging

    ; zero page tables
    xor eax, eax
    mov edi, pagemap - kernel_physical_offset
    mov ecx, (pagemap.end - pagemap) / 4
    rep stosd

    ; setup page tables
    mov eax, 0x03
    mov edi, pagemap.pt - kernel_physical_offset
    mov ecx, 512 * 16

.paging_loop0:
    stosd
    push eax
    xor eax, eax
    stosd
    pop eax
    add eax, 0x1000
    loop .paging_loop0

    ; set up directories
    mov eax, pagemap.pt - kernel_physical_offset;
    or eax, 0x03
    mov edi, pagemap.pd - kernel_physical_offset;
    mov ecx, 16

.paging_loop1:
    stosd
    push eax
    xor eax, eax
    stosd
    pop eax
    add eax, 0x1000
    loop .paging_loop1

    mov eax, pagemap.pd - kernel_physical_offset
    or eax, 0x03
    mov edi, pagemap.pdpt_low - kernel_physical_offset
    stosd
    xor eax, eax
    stosd

    mov eax, pagemap.pd - kernel_physical_offset
    or eax, 0x03
    mov edi, pagemap.pdpt_high - kernel_physical_offset + 511 * 8
    stosd
    xor eax, eax
    stosd

    ; pml4
    mov eax, pagemap.pdpt_low - kernel_physical_offset
    or eax, 0x03
    mov edi, pagemap.pml4 - kernel_physical_offset
    stosd
    xor eax, eax
    stosd

    mov eax, pagemap.pdpt_low - kernel_physical_offset
    or eax, 0x03
    mov edi, pagemap.pml4 - kernel_physical_offset + 256 * 8
    stosd
    xor eax, eax
    stosd

    mov eax, pagemap.pdpt_high - kernel_physical_offset
    or eax, 0x03
    mov edi, pagemap.pml4 - kernel_physical_offset + 511 * 8
    stosd
    xor eax, eax
    stosd

    ; PAE
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    mov eax, pagemap - kernel_physical_offset
    mov cr3, eax
    
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ; load gdt with 64 bit flags
    lgdt [gdt_pointer_lower_half - kernel_physical_offset]
    jmp 0x08:.long_mode - kernel_physical_offset;

.long_mode:
    [bits 64]

    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; enter higher half
    mov rax, .higher_half
    jmp rax

.higher_half:
    mov rsp, kernel_physical_offset + 0xEFFFF0

    lgdt [gdt_pointer]

    call main
.end: