
%define FREE_SPACE 0x9000

ORG 0x7C00
BITS 16

org 0x9000
bits 64
; _entry64:  

; [absolute 0x10000]
; pagetables:
;     ; Layout of aliasing page tables to map all virtual memory to single page,
;     ; each page table level has 3 possible regions: low, high, alias
;     ; (in that order in memory), each level uses two page tables.
;     ; one is the combination of .low and .high with is used to identity
;     ; map the first 2M of virtual memory and the rest is the same as .alias.
;     ; then there is .alias with is the page table used to alias the rest of the pages.
;     ; .alias will be filled with entry pointing to .alias of their lower level table or the page.
;     ; Note: Not all level have have .low, .high and .alias as some do not have seperate
;     ; alias table or seperate high and low parts.
;     pml4: ; PAGE 
;         .low: resq 1
;         .high: resq 511
;     pdp: ; 2 PAGES
;         .low: resq 1
;         .high: resq 511
;         .alias: resq 512
;     pd: ; 2 PAGES
;         .low: resq 1
;         .high: resq 511
;         .alias: resq 512
;     pt: ; 2 PAGES
;         .low: resq 512
;         .alias: resq 512

; Main entry point where BIOS leaves us.

Main:
    jmp 0x0000:.FlushCS               ; Some BIOS' may load us at 0x0000:0x7C00 while other may load us at 0x07C0:0x0000.
                                      ; Do a far jump to fix this issue, and reload CS to 0x0000.

packet: 
    db 0x10
    db 0x00
.blocks: dw 16
.addr: dw 0x7C00
    dw 0
.lba: dd 1
    dd 

load: 
    mov si, packet
    mov dl, 0x80
    int 0x13
    jc .error


.FlushCS:   
    xor ax, ax

    ; Set up segment registers.
    mov ss, ax
    ; Set up stack so that it starts below Main.
    mov sp, Main
    
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    cld

    call CheckCPU                     ; Check whether we support Long Mode or not.
    jc .NoLongMode

    ; Point edi to a free space bracket.
    mov edi, FREE_SPACE
    ; Switch to Long Mode.
    jmp SwitchToLongMode


BITS 64
.Long:
    hlt
    jmp .Long


BITS 16

.NoLongMode:
    mov si, NoLongMode
    call Print

.Die:
    hlt
    jmp .Die


%include "LongModeDirectly.asm"
BITS 16


NoLongMode db "ERROR: CPU does not support long mode.", 0x0A, 0x0D, 0


; Checks whether CPU supports long mode or not.

; Returns with carry set if CPU doesn't support long mode.

CheckCPU:
    ; Check whether CPUID is supported or not.
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
    jz .NoLongMode
    
    mov eax, 0x80000000   
    cpuid                 
    
    cmp eax, 0x80000001               ; Check whether extended function 0x80000001 is available are not.
    jb .NoLongMode                    ; If not, long mode not supported.

    mov eax, 0x80000001  
    cpuid                 
    test edx, 1 << 29                 ; Test if the LM-bit, is set or not.
    jz .NoLongMode                    ; If not Long mode not supported.

    ret

.NoLongMode:
    stc
    ret


; Prints out a message using the BIOS.

; es:si    Address of ASCIIZ string to print.

Print:
    pushad
.PrintLoop:
    lodsb                             ; Load the value at [@es:@si] in @al.
    test al, al                       ; If AL is the terminator character, stop printing.
    je .PrintDone                  	
    mov ah, 0x0E	
    int 0x10
    jmp .PrintLoop                    ; Loop till the null character not found.
	
.PrintDone:
    popad                             ; Pop all general purpose registers to save them.
    ret


; ; Pad out file.
times 510 - ($-$$) db 0
dw 0xAA55
