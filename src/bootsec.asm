[bits 16]

%include "defs.inc"
%include "bios.inc"

extern __bss_start
extern __bss_end
extern __real_bss_start
extern __real_bss_end
extern _loaded16

section .real.bootsec
bits 16
start16:
        xor ax, ax

        mov ss, ax
        mov es, ax
        mov ds, ax
        mov gs, ax

        mov ecx, __bss_end
        mov edi, __bss_start
        sub ecx, edi
        repz stosb ; al is zero from earlier

        mov bx, (0x18000 / 16)
        mov fs, bx
        mov es, bx

        mov ecx, __real_bss_end
        mov edi, __real_bss_start
        sub ecx, edi
        repz stosb ; al is zero from earlier
        
        ; set ES back to zero
        mov es, ax

        mov sp, stack.top

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

section .real.data
DiskError db "DISK", 0x0A, 0x0D, 0x00
stack_top dq -1

section .bss
stack:
    resb 0x1000
.top: resb 0
