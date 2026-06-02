[warning -zeroing]
[bits 16]

%define ADDR_OF_LOCAL(sym) ((sym - $$) + 0x7C00)

%macro live_eval 1
%warning %hex(%[(%eval(%1)])
%endmacro

%define PAGE_PRESENT            (1 << 0)
%define PAGE_WRITE              (1 << 1)
%define PAGE_WRITE_THROUGH      (1 << 3)

%define CODE_SEG     0x0008
%define DATA_SEG     0x0010
%define TASK_SEG     0x0018

extern __bss_start
extern __bss_end
section .real.bootsec
bits 16
start16:
        xor ax, ax
        mov ss, ax


        mov es, ax
        mov ds, ax
        mov gs, ax

        mov sp, stack.top

        mov ax, (0x18000 / 16)
        mov fs, ax

        cld

    
        mov si, DiskPackage
        mov dl, 0x80
        mov ah, 0x42
        int 0x13
        
        jc .disk_error

        jmp _loaded16

.disk_error:
        mov si, DiskError
        call bios_print
        jmp die

die: 
        hlt
        jmp die

bios_print:
    pushad
.loop:
    lodsb                             ; Load the value at [@es:@si] in @al.
    test al, al                       ; If AL is the terminator character, stop printing.
    je .done                 	
    mov ah, 0x0E	
    int 0x10
    jmp .loop
	
.done:
    popad                             ; Pop all general purpose registers to save them.
    ret

DiskPackage: 
        db 0x10
        db 0x00
        dw 127
        dw 0x7E00
        dw 0
        dd 1 ; LBA#1
        dd 0

times (510 - ($ - $$)) db 0
dw 0xAA55

section .bss
stack:
    resb 0x1000
.top: resb 0

section .real.data
DiskError db "DISK", 0x0A, 0x0D, 0x00
UnsupportedCPU db "CPU", 0x0A, 0x0D, 0x00
StartupError db "UNK", 0x0A, 0x0D, 0x00 
stack_top dq -1
Message db "Hello, World!$", 0x0A, 0x0D, 0x00

section .real.text
bits 16
_loaded16:
    mov si, Message
    call bios_print
    
    call __early_map_image

    ; Disable IRQs
    mov al, 0xFF                      ; Out 0xFF to 0xA1 and 0x21 to disable all IRQs.
    out 0xA1, al
    out 0x21, al

    lidt [early_idtr]                        ; Load a zero length IDT so that any NMI causes a triple fault.



    ; Enter long mode.
    mov eax, 10100000b                ; Set the PAE and PGE bit.
    mov cr4, eax
      
    mov edx, pml4                  ; Point CR3 at the PML4.
    mov cr3, edx
      
    mov ecx, 0xC0000080               ; Read from the EFER MSR. 
    rdmsr    


    or eax, 0x00000100                ; Set the LME bit.
    wrmsr

    mov ebx, cr0                      ; Activate long mode -
    or ebx,0x80000001                 ; - by enabling paging and protection simultaneously.
    mov cr0, ebx                    

    cli
    lgdt [GDT.Pointer]                ; Load GDT.Pointer defined below
    

    jmp CODE_SEG:_start64             ; Load CS with 64 bit segment and flush the instruction cache
      
.startup_error: 
        mov si, StartupError
        call bios_print
        jmp die 

.unsupported_cpu:
        mov si, UnsupportedCPU
        call bios_print
        jmp die

; di = offset of target table from fs
; eax = address of first entry
; ebx = address of the rest of the entries
; CLOBBERS: EDI, EAX, EBX
global fill_pagetable
fill_pagetable:

    or eax, (PAGE_PRESENT | PAGE_WRITE)
    mov [fs:di], eax

    mov eax, ebx
    or eax, (PAGE_PRESENT | PAGE_WRITE)

    mov bx, 511

    .loop:
        add di, 8

        mov [fs:di], eax

        dec bx
        jnz .loop
    

    ret


__early_map_image:
    push eax
    push edi
    push ecx

    mov edi, pml4.rel
    mov eax, pdp
    mov ebx, dyndata.alias_pdp
    call fill_pagetable

    mov edi, pdp.rel
    mov eax, pd
    mov ebx, dyndata.alias_pd
    call fill_pagetable

    mov edi, pd.rel
    mov eax, pt
    mov ebx, dyndata.alias_pt
    call fill_pagetable

    mov eax, backing_page
    or eax, (PAGE_PRESENT | PAGE_WRITE)
    mov [fs:pt.rel], eax

    ; identity map range from 0x1000 to 0x18000
    mov edi, pt.rel
    mov ecx, (PAGE_PRESENT | PAGE_WRITE)
    .loop:
        add edi, 8
        add ecx, 0x1000

        mov [fs:edi], ecx

        cmp ecx, 0x17000
        jl .loop

    pop eax
    pop edi
    pop ecx

    ret



%define IST_INDEX 1
%macro tss_segment 2
    %push tss
    %define _base ( %1 )
    %define _limit ( %2 )
    dw (_limit & 0xFFFF)
    dw (_base & 0xFFFF)

    db ((_base >> 16) & 0xFF)
    db 0x89 ; Present 64-bit TSS (DPL 0)

    db ((_limit >> 16) & 0xF)
    db ((_base >> 24) & 0xFF)

    dd ((_base >> 32) & 0xFFFFFFFF)
    dd 0x0
    %pop 
%endmacro

__init_gdt:


section .real.data
GDT:
.Null:
    dq 0x0000000000000000             ; Null Descriptor - should be present.

.Code:
    dq 0x00209A0000000000             ; 64-bit code descriptor (exec/read).
    dq 0x0000920000000000             ; 64-bit data descriptor (read/write).

.tss:
    dw (TSS.end - TSS - 1)
    dw TSS
    dw 0x8900
    dw 0x0
    dq 0x0

ALIGN 4
    db 0
.Pointer:
    dw $ - GDT - 1                                   ; 16-bit Size (Limit) of GDT.
    dd GDT                            ; 32-bit Base Address of GDT. (CPU will zero extend to 64-bit)

TSS:
    dd 0
    ; we don't use the RSP{0,1,2} pointers
    times 3 dq 0x0
    dq 0
    ; ist 1, used in nearly every interrupt*.
    dq dyndata.trap_stack

    ; all the other ISTs are unused
    times 6 dd 0x00

    dd 0x0

    ; no io protection bitmap
    dw $ - TSS
.end: resb 0

%define IST_INDEX 1
%macro idt_entry 2
    %push idte
    %define _offset ( %1 )
    %define _type_attrs %cond(%2, 0x8E, 0x8F)
    dw (_offset & 0xFFFF)
    dw CODE_SEG
    db IST_INDEX
    db _type_attrs
    dw ((_offset >> 16) & 0xFFFF)
    dd ((_offset >> 32) & 0xFFFFFFFF)
    dd 0x0
    %pop idte
%endmacro



%define ALIGN_PADDING(addr, align) (align - (addr & (align - 1))) & (align - 1);
%macro ALIGN_PAD 1
    times ALIGN_PADDING(ADDR_OF_LOCAL($), 0x1000) db 0
%endmacro

early_idtr:
    dw 0
    dd 0x0

%define INT_STACK_FAULT 0x0C
%define INT_GENERAL_PROTECTION 0x0D
%define INT_PAGE_FAULT 0x0E

section .bss
ALIGN 0x1000
;; idt for the first 64 interrupts
IDT:
    ; other exceptions
    times 256 resq 2

section .data
ALIGN 4
IDTR: 
    dw (256 * 16) - 1                                
    dq IDT  

section .text
bits 64
_start64:
    mov ax, DATA_SEG
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    lidt [IDTR]

    mov ax, TASK_SEG
    ltr ax

    jmp _start

;;; LONG MODE ;;;


%define interrupt_begin interrupt_begin_ rax, rbx, rcx, rdx, rsi, rdi, r11, r12
%macro interrupt_begin_ 1-*
    nop

    %push intctx
    push rbp
    mov rbp, rsp

    %define old_rsp [rbp - 32]
    %define old_rflags [rbp - 16 - 8]
    %define old_rip [rbp - 8]
    %define old_rbp [rbp]

    %define __saved_regs  %[%{-1:1}]
    %assign __save_depth 1
    %rep  %0
        %define old_%[%1] qword [rbp + (__save_depth * 8)]
        push    %1
    %rotate 1 
    %endrep 

%endmacro

%define interrupt_end interrupt_end_ __saved_regs
%macro interrupt_end_ 1-*
    pop rbp

    %rep %0
        pop    %1
    %rotate 1 
    %endrep 
    %pop intctx

    iret
%endmacro

handle_ss_fault:
handle_gp_fault:
    ; fast skip over non canonical region
    mov rax, [rsp + 32]
    add rax, 8
    mov rbx, rax
    and rax, 0x7FFFFFFFFFFF
 
    hlt
    iretq
.handler: 
        mov rax, qword [rsp + 32]
    and rax, 0x7FFFFFFFFFFF
    hlt

%define _IDTE_META (\
    1 << 31 \
    | 0x8F << 24 \
    | IST_INDEX << 16 \
    | CODE_SEG \
)
; rax = entry num
; rbx = handler
set_idt_entry:
    shl rax, 4
    add rax, IDT

    mov dword [rax + 2], _IDTE_META

    mov word [rax], bx

    shr ebx, 4
    mov word [rax + 6], bx

    ret

; %warning %[%eval($ - handle_ss_fault)]

; setup links between alias page tables levels
; and final page table to point to single backing page
interlink_alias_pagetables:
    push rcx
    push rdi
    push rax

    ; PDP
    mov rcx, 512
    mov rdi, dyndata.alias_pdp
    mov rax, dyndata.alias_pd
    or rax, (PAGE_PRESENT | PAGE_WRITE)
    rep stosq

    ; PD
    mov rcx, 512
    mov rdi, dyndata.alias_pd
    mov rax, dyndata.alias_pt
    or rax, (PAGE_PRESENT | PAGE_WRITE)
    rep stosq

    ; PT
    mov rcx, 512
    mov rdi, dyndata.alias_pt
    mov rax, backing_page
    or rax, (PAGE_PRESENT | PAGE_WRITE)
    rep stosq

    ; flush page caches
    mov rax, cr3
    mov cr3, rax

    pop rax
    pop rdi
    pop rcx

    ret

global _start
_start:
    mov rax, INT_STACK_FAULT
    mov rbx, handle_ss_fault
    call set_idt_entry

    mov rax, INT_GENERAL_PROTECTION
    mov rbx, handle_gp_fault
    call set_idt_entry

    call interlink_alias_pagetables

    mov rax, [-1]
 
    mov rcx, 0x1000000000
    mov r11, counter_fun
    call run_fun_bounded

    jmp $

counter_fun:
    cmp rax, rcx
    je .stop
    inc rax
    call counter_fun
.stop: ret

; run an recursive function on bounded yet giant stack. ;)
; allows the function* given in [r11] to recurce 30+ *trillion* times without tail calls.
; NOTE: the function must meet certain requirements. See `counter_fun` for details.
run_fun_bounded:
    mov [dyndata.old_stack], rsp
    mov rsp, 0xFFFF800000000000

    call r11

    mov [dyndata.reached_rsp], rsp
    mov rsp, [dyndata.old_stack] ; restore

    ret

section .real.bss
align 0x1000
pml4:
    .rel: equ ($ - 0x18000)
    resq 512
pdp:
    .rel: equ ($ - 0x18000)
    resq 512
pd:
    .rel: equ ($ - 0x18000)
    resq 512
pt:
    .rel: equ ($ - 0x18000)
    resq 512


; null page
; dq 0x21000 | (PAGE_PRESENT | PAGE_WRITE)
; %assign addr 0x1000
; %rep (0x17000) / 0x1000
;     dq addr | (PAGE_PRESENT | PAGE_WRITE)
; %assign addr addr+0x1000
; %endrep
; dq 0xB8000 | (PAGE_PRESENT | PAGE_WRITE | PAGE_WRITE_THROUGH)
; dq 0x00


%include "layout.asm"