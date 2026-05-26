[map all mapfile.text]
[org 0x7C00]

[bits 16]

%define ADDR_OF_LOCAL(sym) ((sym - $$) + 0x7C00)
%define FAR_READ(sym) [fs:((sym) - $$ + 512)]

%define PAGE_PRESENT    (1 << 0)
%define PAGE_WRITE      (1 << 1)
 
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

times (510 - ($ - $$)) db 0
dw 0xAA55

UnsupportedCPU db "CPU", 0x0A, 0x0D, 0x00
StartupError db "UNK", 0x0A, 0x0D, 0x00 


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

check_cpu: ; is the CPU actually supported, does it have say long mode.
    pushfd                            ; Get flags in EAX register.
    
    pop eax
    mov ecx, eax  
    xor eax, 0x200000 
    push eax 
    popfd

    pushfd 
    pop eax
    xor eax, ecx
    shr eax, 21 
    and eax, 1                        ; Check whether bit 21 is set or not. If EAX now contains 0, CPUID isn't supported.
    push ecx
    popfd 

    test eax, eax
    jz .unsupported
    
    mov eax, 0x80000000   
    cpuid                 
    
    cmp eax, 0x80000001               ; Check whether extended function 0x80000001 is available are not.
    jb .unsupported

    mov eax, 0x80000001  
    cpuid                 
    test edx, 1 << 29                 ; Test if the LM-bit, is set or not.
    jz .unsupported

    ret

.unsupported:
    stc
    ret

Message db "Hello, World!", 0x0A, 0x0D, 0x00

_loaded16:

       mov si, Message
        call bios_print
    
    cli 
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

    hlt

    cli
    lgdt FAR_READ(GDT.Pointer)                ; Load GDT.Pointer defined below

      
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

_start:
    int 0xAA
    jmp $

paging:
  .pml4:
    dq ADDR_OF_LOCAL(paging.pdp) | (PAGE_PRESENT | PAGE_WRITE)
    times 511 dq dyndata.alias_pdp | (PAGE_PRESENT | PAGE_WRITE)
  .pdp:
    dq ADDR_OF_LOCAL(paging.pd) | (PAGE_PRESENT | PAGE_WRITE)
    times 511 dq dyndata.alias_pd | (PAGE_PRESENT | PAGE_WRITE)
  .pd:
    dq ADDR_OF_LOCAL(paging.pt) | (PAGE_PRESENT | PAGE_WRITE)
    times 511 dq dyndata.alias_pt | (PAGE_PRESENT | PAGE_WRITE)
  .pt:
    ; null page
    dq 0x1000 | (PAGE_PRESENT | PAGE_WRITE)
    %assign addr 0x1000
    %rep 20
      dq addr | (PAGE_PRESENT | PAGE_WRITE)
    %assign addr addr+0x1000 
    %endrep


; pad to 64KiB
times ((64 * 1024) - ($ - $$)) db 0


%include "layout.asm"