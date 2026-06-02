
section .bss
align 0x1000
dyndata:
    .alias_pdp: resq 512
    .alias_pd: resq 512
    .alias_pt resq 512
    .cursor_x: resw 0
    .cursor_y: resw 0
    .old_stack: resq 1
    .reached_rsp: resq 1
    resq 511
    .old_rsp: resq 1
    .trap_stack: resq 0





section .real.bss
align 0x1000
backing_page: resb 0x1000
