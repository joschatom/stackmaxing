NAME = stkmaxing

SRCDIR = src
BUILDDIR = build

ASM = nasm
OBJCOPY = objcopy
LD = ld

SOURCES = $(wildcard $(SRCDIR)/*.asm)

all: build link $(SOURCES)

build: linker.lds Makefile $(SOURCES)
	$(ASM) -felf64 $(SOURCES) -o build/$(NAME).o -g
link: build linker.lds $(SOURCES)
	$(LD) -T linker.lds build/$(NAME).o -o build/$(NAME).elf --print-map-locals -Map build/$(NAME).map -z defs
	$(OBJCOPY) -S -O binary build/$(NAME).elf build/$(NAME).bin

