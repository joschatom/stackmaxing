
%define ADDR_OF_LOCAL(sym) ((sym - $$) + 0x7C00)

%macro live_eval 1
%warning %hex(%[(%eval(%1)])
%endmacro

%define PAGE_PRESENT            (1 << 0)
%define PAGE_WRITE              (1 << 1)
%define PAGE_WRITE_THROUGH      (1 << 3)

%define CODE_SEG     0x0008
%define DATA_SEG     0x0010
%define TASK_SEG     0x0016

;ta
extern die