
MEMORY {
    PREMEM (W!I) : ORIGIN = 0x1000, LENGTH = (0x7c000 - 0x1000)
    IMAGE (WX) : ORIGIN = 0x7c00, LENGTH = 64K
    POSTMEM (WX!I) : ORIGIN = 0x18000, LENGTH = 64K
}

SECTIONS {


    . = 0x1000;

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss.* .bss)        
        __bss_end = .;
    } >PREMEM

    . = 0x7c00;

    .real.text : {
        __start_real_text = .;
        *(.real.bootsec);
        *(.real.text .real.text.*);
        __end_real_text = .;
    } >IMAGE

    .real.data : {
        __start_real_data = .;
        *(.real.data .real.data.*);
        __end_real_data = .;
    } >IMAGE

    ASSERT((. < 64K), "realmode code/data not within 64K segment range")

    .text :  {
        __start_text = .;
        *(.text .text.*);
        __end_text = .;
    } >IMAGE

    .data : { 
        __start_data = .;
        *(.data .data.*)
        __end_data = .;
    } >IMAGE

    .padding : {
        . = ABSOLUTE(ORIGIN(IMAGE) + LENGTH(IMAGE) - 1);
        BYTE(0x0)
    } >IMAGE =0x00

    . = 0x18000;

    .virtual_pages (NOLOAD) : {
        __video_page = ABSOLUTE(0x18000);
        __guard_page = ABSOLUTE(0x19000);
        __lower_half_start = ABSOLUTE(0x20000);
    }

    .real.bss (NOLOAD) : {
        __real_bss_start = .;
        *(.real.bss real.bss.*)
        __real_bss_end = .;
    } > POSTMEM

    /DISCARD/ : {
        *(.got)
        *(.iplt*)
        *(.igot*)
        *(.got.plt)
        *(.got*)
        *(.rela*)
        *(.rel*)
        *(.dynamic)
        *(.dynsym)
        *(.dynstr)
        *(.hash)
        *(.gnu.hash)
    }
}