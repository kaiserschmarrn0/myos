%include "constants.asm"

; YO this file should not have to exist

[bits 64]

global gdt_pointer
global gdt_pointer_lower_half

; This one will be the GDT we will load
section .data

align 16
gdt_pointer_lower_half:
    dw gdt_pointer.end - gdt_pointer.start - 1; size
    dd gdt_pointer.start - kernel_physical_offset ; start

align 16
gdt_pointer:
    dw .end - .start - 1
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

.unreal_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
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

section .text

global loadTSS:function (loadTSS.end - loadTSS)
loadTSS:
    ;addr in RDI
    push rbx
    mov eax, edi
    mov rbx, gdt_pointer.tss_low
    mov word [rbx], ax
    mov eax, edi
    and eax, 0xFF0000
    shr eax, 16
    mov rbx, gdt_pointer.tss_mid
    mov byte [rbx], al
    mov eax, edi
    and eax, 0xFF000000
    shr eax, 24
    mov rbx, gdt_pointer.tss_high
    mov byte [rbx], al
    mov rax, rdi
    shr rax, 32
    mov rbx, gdt_pointer.tss_upper32
    mov dword [rbx], eax
    mov rbx, gdt_pointer.tss_flags1
    mov byte [rbx], 10001001b
    mov rbx, gdt_pointer.tss_flags2
    mov byte [rbx], 0
    pop rbx
    ret
.end: