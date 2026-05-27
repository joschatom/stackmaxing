[bits 64]

counter_fun:
    cmp rax, rcx
    je .stop
    inc rax
    call counter_fun
.stop: ret

global _start
_start:
   mov rcx, 1000000000000 ; 1 billion
   xor rax, rax
   call counter_fun
