[map all mapfile.text]
[org 0x7C00]
[bits 16]

%define load_start 0x7C00 + 512

%define PAGE_PRESENT    (1 << 0)
%define PAGE_WRITE      (1 << 1)
 
%define CODE_SEG     0x0008
%define DATA_SEG     0x0010

section .boot start=0x7C00
_entry16: 
        jmp 0x00:start16

start16:
        xor ax, ax
        mov ss, ax

        mov sp, _entry16

        mov ds, ax
        mov es, ax
        mov fs, ax
        mov gs, ax

        cld

        call check_cpu
        jc .unsupported_cpu
        
        mov si, DiskPackage
        mov dl, 0x80
        mov ah, 0x42
        int 0x13
        jc .disk_error

        call setup_early_pagetables

        jmp _loaded16

.startup_error: 
        mov si, StartupError
        call bios_print
        jmp die 
 
.disk_error:
        mov si, DiskError
        call bios_print
        jmp die

.unsupported_cpu:
        mov si, UnsupportedCPU
        call bios_print
        jmp die

%macro __pagetlb_setea 3
        lea eax, %2
        or eax, %3
        mov [%1], eax
%endmacro

setup_early_pagetables: ; identity map the first 2MiB minus one 4KiB Page.
        ; setup low PML4, PDP and PD with the respective effective addresses.
        __pagetlb_setea pml4.low, [pdp.low], (PAGE_PRESENT | PAGE_WRITE)
        __pagetlb_setea pdp.low, [pd.low], (PAGE_PRESENT | PAGE_WRITE)
        __pagetlb_setea pd.low, [pt.low], (PAGE_PRESENT | PAGE_WRITE)

        ; setup low PT, identity mapping
        lea di, [pt.low] 
        mov eax, PAGE_PRESENT | PAGE_WRITE
        
        .loop:
            mov [di], eax
            add eax, 0x1000
            add di, 8
            cmp eax, 0x200000 - 0x1000  ; end
            jb .loop

        ; the high part of the PML4 we set to all zeros so invalid acceses
        ; trigger a fault instead of being ub we can still
        ; avoid filling all the tables with zeros.
        lea di, [pml4.high]
        xor eax, eax
        mov ecx, 0x1000
        rep stosb

        ; we leave the last page of the first 2M unmapped as a guard page
        ; the rest of the page table remains uninitalized memory
        ; expect for the pml4 with is filled with zeros
        ret
die: 
        hlt
        jmp die

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

section .bootdata follows=.boot
DiskError db "ERROR: Failed to read from boot disk.", 0x0A, 0x0D, 0x00
UnsupportedCPU db "ERROR: CPU is not supported.", 0x0A, 0x0D, 0x00
StartupError db "ERROR: Startup of real code failed", 0x0A, 0x0D, 0x00 

DiskPackage: 
        db 0x10
        db 0x00
        dw 16
        dw load_start
        dw 0
        dd 1 ; LBA#1
        dd 0
        
section .bootmagic start=(load_start - 2)
dw 0xAA55

section .text follows=.bootmagic
_loaded16:
                mov si, Message
        call bios_print

        ; TODO: Switch directly to long mode

        jmp die

section .data
Message db "Hello, World!", 0x0A, 0x0D, 0x00

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
    dd GDT                            ; 32-bit Base Address of GDT. (CPU will zero extend to 64-bit)

align 4
IDTR:
        .Limit dw 0
        .Base dd 0

section .padding
times (0x2000 + 512)-($-$$) db 0

; alias page tables (included), code cave page tabes (included). root page table (pml4), alised page
; dynamically created: aliasing pdp, pd and the code cave pdp, pd (32Kib)

section .bss nobits
align 0x1000
pagetables:
pt: 
        .low resq 512
        .alias resq 512
pml4:
        .low resq 1
        .high resq 511
pdp:
        .low resq 1
        .high resq 511
        .alias resq 512
pd:
        .low resq 1
        .high resq 511
        .alias resq 512
pad: resq 512
pagetables.size equ $ - pagetables
