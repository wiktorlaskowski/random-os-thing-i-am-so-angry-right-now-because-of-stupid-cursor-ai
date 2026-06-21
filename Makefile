ASM := nasm
BUILD := build
IMG := $(BUILD)/pmoms.img
BOOT := src/boot/pmoms.asm
BIN := $(BUILD)/pmoms.bin

.PHONY: all image clean
all: image

$(BUILD):
	mkdir -p $(BUILD)

$(BIN): $(BOOT) | $(BUILD)
	$(ASM) -f bin $< -o $@

image: $(IMG)

$(IMG): $(BIN) | $(BUILD)
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$< of=$@ conv=notrunc status=none
	@echo "Built $(IMG) - attach as a floppy disk in VirtualBox."

clean:
	rm -rf $(BUILD)
