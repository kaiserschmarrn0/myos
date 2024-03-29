[org 0x8000]
[bits 16]

call await
cli
nop
nop
mov al, 0xFF
out 0x21, al
out 0xA1, al
nop
nop
sti
call await
ret

await:
    pusha
    mov bx, 0xFFFF

.loop:
    mov cx, 16
    mov di, dummy1
    mov si, dummy2
    rep movsb
    dec bx
    jnz .loop
    popa
    ret

dummy1 times 16 db 0
dummy2 times 16 db 0