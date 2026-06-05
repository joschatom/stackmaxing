

section .text

; see format.inc
format_oct:
    push rbx
    push rcx
.loop:
	mov bl, al
	or bl, 0b110000 ; add 48
	and bl, 0b110111 ; discard the 4th bit as well as the upper bits
	shr rax, 3

    mov byte [rdi + rcx], bl
    dec rcx ; decrement the buffer size to zero
    jnz .loop

    pop rcx
    pop rbx
    ret