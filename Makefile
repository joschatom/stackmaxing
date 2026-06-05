NAME = stkmaxing

SRCDIR = src
BUILDDIR = build
INCLUDEDIR = include
OBJDIR = $(BUILDDIR)/objects

ASM = nasm
OBJCOPY = objcopy
LD = ld

ASMFLAGS = -felf64 -g -Iinclude

SOURCES = $(strip $(shell find src -name '*.asm'))
OBJECTS = $(patsubst src/%.asm,$(OBJDIR)/%.o,$(SOURCES))

all: $(BUILDDIR)/$(NAME).bin

$(BUILDDIR)/$(NAME).bin: $(BUILDDIR)/$(NAME).elf
	@echo OBJCOPY $(notdir $<) $(notdir $@)
	@$(OBJCOPY) -S -O binary $< $@

$(OBJDIR)/%.o: src/%.asm $(SOURCES)
	@echo ASSEMBLE $(notdir $<)
	@$(ASM) $< -o $@ $(ASMFLAGS)

$(BUILDDIR)/$(NAME).elf: linker.lds $(OBJECTS)
	@cd $(notdir $(BUILDDIR))
	@echo LD $(notdir $(OBJECTS))
	@$(LD) -T linker.lds $(OBJECTS) -o $@ --print-map-locals -Map $(BUILDDIR)/$(NAME).map -z defs 

ARTIFACTS = $(BUILDDIR)/$(NAME).elf $(BUILDDIR)/$(NAME).bin $(BUILDDIR)/$(NAME).map \
	$(OBJECTS)

define dep_makefile_target
$(info DEPEND $(1))
$(shell $(ASM) $(ASMFLAGS) $(1) \
	-M -MQ "$(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(1))" \
	| tr -d '\\\n'\
)
endef

$(foreach src,$(SOURCES),$(eval $(call dep_makefile_target,$(src))))

abcd:
	echo $(call dep_makefile_target,src/main.asm)
	

.PHONY: clean
clean:
	rm -f $(ARTIFACTS)