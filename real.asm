%include "constants.asm"

section .data

%define flush_irqs_bin_size flush_irqs_bin_end - flush_irqs_bin
flush_irqs_bin: incbin "flush_irqs.bin"
flush_irqs_bin_end:

%define real_init_bin_size real_init_bin_end - real_init_bin
real_init_bin: incbin "real_init.bin"
real_init_bin_end:

%define e820_bin_size e820_bin_end - e820_bin
e820_bin: incbin "e820.bin"
e820_bin_end:

[bits 64]

section .text

global real_routine:function (real_routine.end - real_routine)
real_routine:
    push rsi
    push rcx

    mov rsi, real_init_bin
    mov rdi, 0x1000
    mov rcx, real_init_bin_size
    rep movsb

    pop rcx
    pop rsi
    mov rdi, 0x8000
    rep movsb

    mov rax, 0x1000
    call rax

    ret
.end:

global flush_irqs:function (flush_irqs.end - flush_irqs)
flush_irqs:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rsi, flush_irqs_bin
    mov rcx, flush_irqs_bin_size
    call real_routine

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret
.end:

global get_e820:function (get_e820.end - get_e820)
get_e820:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    sub rbx, kernel_physical_offset
    mov rsi, e820_bin
    mov rcx, e820_bin_size
    call real_routine

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.end: