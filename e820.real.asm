[org 0x8000]
[bits 16]

push ebx
xor ebx, ebx

loop:
    mov eax, 0xe820
    mov ecx, 24
    mov edx, 0x534d4150
    mov edi, e820_entry
    int 0x15
    jc done_noset
    test ebx, ebx
    jz done_set
    pop edi
    mov esi, e820_entry
    mov ecx, 24
    a32 o32 rep movsb
    push edi
    jmp loop

done_set:
    pop edi
    mov esi, e820_entry
    mov ecx, 24
    a32 o32 rep movsb
    jmp done

done_noset:
    pop edi
    jmp done

done:
    xor al, al
    mov ecx, 24
    a32 o32 rep stosb
    ret

align 16
e820_entry:
    times 24 db 0