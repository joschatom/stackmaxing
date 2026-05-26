
absolute 0x1000
dyndata:
    .alias_pdp: resq 512
    .alias_pd: resq 512
    .alias_pt resq 512

absolute 0x7000
early_stack: resb 0x500

; 0x7C00 to 0x18000 is the image

absolute 0x7C00
bootsec: resb 512
loaded_binary: resb (64 * 1024) - 512

absolute 0x18000
video_page: resq 512

; no memory after 2M (so we only need 2 Page Tables).

