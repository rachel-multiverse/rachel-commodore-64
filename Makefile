# Rachel C64 - Makefile
# Requires: acme (assembler), vice (emulator)

ACME = acme
VICE = x64sc
SRC = src/main.asm
OUT = build/rachel.prg

# Default target
all: $(OUT)

# Build the PRG file
$(OUT): src/*.asm
	@mkdir -p build
	$(ACME) -f cbm -o $(OUT) --report build/report.txt $(SRC)
	@echo "Built: $(OUT)"

# Run in VICE (no network)
run: $(OUT)
	$(VICE) $(OUT)

# Run with RS232->TCP bridge for network testing
# Requires a server listening on localhost:19840
test-net: $(OUT)
	$(VICE) -rsuser -rsuserbaud 2400 -rsuserdev 2 \
		-rsdev2 "|nc localhost 19840" $(OUT)

# Clean build artifacts
clean:
	rm -rf build/*

# Show assembly report
report: $(OUT)
	@cat build/report.txt

.PHONY: all run test-net clean report
