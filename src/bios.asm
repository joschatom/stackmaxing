
section .real.text
bits 16
global bios_print:function
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