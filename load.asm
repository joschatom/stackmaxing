[map all mapfile.text]
[org 0x7C00]

[bits 16]

%define ADDR_OF_LOCAL(sym) ((sym - $$) + 0x7C00)
%define FAR_READ(sym) [fs:((sym) - $$ + 512)]

%define PAGE_PRESENT            (1 << 0)
%define PAGE_WRITE              (1 << 1)
%define PAGE_WRITE_THROUGH      (1 << 3)

%define CODE_SEG     0x0008
%define DATA_SEG     0x0010

start16:
        xor ax, ax
        mov ss, ax

        mov sp, 0x7C00


        mov es, ax
        mov ds, ax
        mov gs, ax

        mov ax, (0x7E00 / 16)
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

DiskError db "DISK", 0x0A, 0x0D, 0x00
UnsupportedCPU db "CPU", 0x0A, 0x0D, 0x00
StartupError db "UNK", 0x0A, 0x0D, 0x00 



times (510 - ($ - $$)) db 0
dw 0xAA55

GDT:
.Null:
    dq 0x0000000000000000             ; Null Descriptor - should be present.

.Code:
    dq 0x00209A0000000000             ; 64-bit code descriptor (exec/read).
    dq 0x0000920000000000             ; 64-bit data descriptor (read/write).
      
ALIGN 4
    dw 0                              ; Padding to make the "address of the GDT" field aligned on a 4-byte boundary

.Pointer:
    dw $ - GDT - 1                    ; 16-bit Size (Limit) of GDT.
    dd ADDR_OF_LOCAL(GDT)                            ; 32-bit Base Address of GDT. (CPU will zero extend to 64-bit)

align 4
IDTR:
        .Limit dw 0
        .Base dd 0

stack_top dq -1
Message db "Hello, World!$", 0x0A, 0x0D, 0x00

_loaded16:

       mov si, Message
        call bios_print
    
    ; Disable IRQs
    mov al, 0xFF                      ; Out 0xFF to 0xA1 and 0x21 to disable all IRQs.
    out 0xA1, al
    out 0x21, al

    lidt FAR_READ(IDTR)                        ; Load a zero length IDT so that any NMI causes a triple fault.

    ; Enter long mode.
    mov eax, 10100000b                ; Set the PAE and PGE bit.
    mov cr4, eax
      
    mov edx, paging.pml4                  ; Point CR3 at the PML4.
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

      
    jmp CODE_SEG:.long             ; Load CS with 64 bit segment and flush the instruction cache
      
.startup_error: 
        mov si, StartupError
        call bios_print
        jmp die 

.unsupported_cpu:
        mov si, UnsupportedCPU
        call bios_print
        jmp die

[bits 64]

.long:
    mov ax, DATA_SEG
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    jmp _start

;;; LONG MODE ;;;


; setup links between alias page tables levels
; and final page table to point to single backing page
interlink_alias_pagetables:
    push rcx
    push rdi
    push rax

    ; PDP
    mov rcx, 512
    mov rdi, dyndata.alias_pdp
    mov rax, dyndata.alias_pd | (PAGE_PRESENT | PAGE_WRITE)
    rep stosq

    ; PD
    mov rcx, 512
    mov rdi, dyndata.alias_pd
    mov rax, dyndata.alias_pt | (PAGE_PRESENT | PAGE_WRITE)
    rep stosq

    ; PT
    mov rcx, 512
    mov rdi, dyndata.alias_pt
    mov rax, backing_page | (PAGE_PRESENT | PAGE_WRITE)
    rep stosq

    ; flush page caches
    mov rax, cr3
    mov cr3, rax

    pop rax
    pop rdi
    pop rcx

    ret

_start:
    mov al, 'H'          ; Character 'H'
    mov ah, 0x07         ; Attribute: Light gray text on black background
    mov [0x18000], ax      ; Write both bytes to the screen

    call interlink_alias_pagetables

    mov rax, [-1]
 
    mov rcx, 1000000000
    mov r11, counter_fun
    call run_fun_bounded

    jmp guard_page

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
    mov rsp, 0x1000

    call r11

    mov [dyndata.reached_rsp], rsp
    mov rsp, [dyndata.old_stack] ; restore

    ret


%define ALIGN_PADDING(addr, align) (align - (addr & (align - 1))) & (align - 1);
%macro ALIGN_PAD 1
    times ALIGN_PADDING(ADDR_OF_LOCAL($), 0x1000) db 0
%endmacro

ALIGN_PAD 0x1000
paging:
  .pml4:
    dq ADDR_OF_LOCAL(paging.pdp) | (PAGE_PRESENT | PAGE_WRITE)
    %ifdef QEMU_MEMORY_DEBUG
    dq dyndata.alias_pdp | (PAGE_PRESENT | PAGE_WRITE)
    times 510 dq 0x00
    %else 
    times 511 dq dyndata.alias_pdp | (PAGE_PRESENT | PAGE_WRITE)
    %endif
  .pdp:
    dq ADDR_OF_LOCAL(paging.pd) | (PAGE_PRESENT | PAGE_WRITE)
    times 511 dq dyndata.alias_pd | (PAGE_PRESENT | PAGE_WRITE)
  .pd:
    dq ADDR_OF_LOCAL(paging.pt) | (PAGE_PRESENT | PAGE_WRITE)
    times 511 dq dyndata.alias_pt | (PAGE_PRESENT | PAGE_WRITE)
  .pt:
    ; null page
    dq 0x21000 | (PAGE_PRESENT | PAGE_WRITE)
    %assign addr 0x1000
    %rep (0x17000) / 0x1000
      dq addr | (PAGE_PRESENT | PAGE_WRITE)
    %assign addr addr+0x1000
    %endrep
    dq 0xB8000 | (PAGE_PRESENT | PAGE_WRITE | PAGE_WRITE_THROUGH)
    dq 0x00


%if (($ - $$) > (64 * 1024))
%error "Code or Data too large, maximum is 64KiB"
%else
times ((64 * 1024) - ($ - $$)) db 0
%endif
; pad to 64KiB

%include "layout.asm"