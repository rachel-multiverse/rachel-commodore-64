# Rachel C64 - Makefile
# Requires: asm198x (assembler), VICE (optional emulator)

ASM198X ?= asm198x
ACME ?= acme
VICE = x64sc
SRC = src/main.asm
OUT = build/rachel.prg

# Default target
all: $(OUT)

# Build the PRG file
$(OUT): src/*.asm
	@mkdir -p build
	$(ASM198X) --dialect acme --prg -I . --listing=build/report.txt $(SRC) -o $(OUT)
	@echo "Built: $(OUT)"

# Differential oracle: prove the family assembler remains byte-identical to ACME.
reference-parity: $(OUT)
	$(ACME) -f cbm -o build/rachel-acme.prg $(SRC)
	cmp $(OUT) build/rachel-acme.prg

# Run in VICE (no network)
run: $(OUT)
	$(VICE) $(OUT)

# Run with RS232->TCP bridge for network testing
# Requires a server listening on localhost:19840
test-net: $(OUT)
	$(VICE) -rsuser -rsuserbaud 2400 -rsuserdev 2 \
		-rsdev2 "|nc localhost 19840" $(OUT)

# Run the client codec against the canonical RUBP fixtures under Emu198x
conformance:
	python3 conformance/run.py

# Clean build artifacts
clean:
	rm -rf build/*

# Show assembly report
report: $(OUT)
	@cat build/report.txt

.PHONY: all run test-net conformance reference-parity clean report
