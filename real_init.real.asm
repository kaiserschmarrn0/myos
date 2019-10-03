[org 0x1000]
[bits 64]

; save stack
mov qword [saved_stack], rsp

; save arg
mov dword [arg], ebx

; same lmode idt
sidt [long_mode_idt]
; save lmode gdt
sgdt [long_mode_gdt]

; load real mode idt
lidt [real_mode_idt]

; save cr3
mov rax, cr3
mov dword [cr3_reg], eax

; load 16 bit segments
jmp far dword [pointer16]

pointer16:
    dd protected_mode_16
    dw 0x28

protected_mode_16:
    [bits 16]

    mov ax, 0x30
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; leave compat mode
    mov eax, cr0
    and eax, 01111111111111111111111111111110b
    mov cr0, eax

    ; leave long mode
    mov ecx, 0xC0000080
    rdmsr

    and eax, 0xFFFFFEFF
    wrmsr

    ; load real mode segments
    jmp 0x0000:real_mode

real_mode:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ax, 0x1000
    mov ss, ax
    mov esp, 0xFFF0

    ; get arg
    mov ebx, dword [arg]

    ; start routine
    sti
    call 0x8000
    cli

    ; temp gdt
    lgdt [gdt_pointer]

    ; load cr3
    mov eax, dword [cr3_reg]
    mov cr3, eax

    mov ecx, 0xC0000080
    rdmsr

    or eax, 0x00000100
    wrmsr

    ; enter long mode
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax

    ; long mode segments
    jmp 0x08:.long_mode

.long_mode:
    [bits 64]

    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; lmode idt
    lidt [long_mode_idt]
    ; lmode gdt
    lgdt [long_mode_gdt]

    ; stack
    mov rsp, qword [saved_stack]

    ret

; section?
data:

align 4
long_mode_idt:
    dw 0
    dq 0

align 4
real_mode_idt:
    dw 0x3FF
    dq 0

align 4
long_mode_gdt:
    dw 0
    dq 0

arg dd 0
cr3_reg dd 0
saved_stack dq 0

%include "gdt_fields.asm"