bits 64

%define STACK_FRAME_ALIGN 3

section .text

; calcuates stack depth
; rbx = stack pointer
; returns depth in RAX


global calc_stack_depth:function
calc_stack_depth:
    test rbx, ~0xFFF
    jnz .highmem
    
    mov rax, 0x1000
    sub rax, rbx
    shr rax, STACK_FRAME_ALIGN
    ret
    
.highmem:

    push rbx
    mov rax, rbx
    
    ; higher half stack size
    mov rbx, 0x7fffffffffff
    not rax
    and rax, rbx

    add rax, 0x1000
    
    ; lower half stack size
    mov rbx, 0x7ffffffdffff
    sub rbx, [rsp]
    jc .final
    add rax, rbx
    
    .final:
        pop rcx
        pop rbx
        shr rax, STACK_FRAME_ALIGN
        ret
        