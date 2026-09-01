# Rachel C64 - Makefile
# Requires: asm198x (assembler), VICE (optional emulator)

ASM198X ?= asm198x
ACME ?= acme
VICE = x64sc
SRC = src/main.asm
OUT = build/rachel.prg
E2E_OUT = build/rachel-e2e.prg
FLAGS = build/build_flags.asm

# Default target
all: $(OUT)

# Build the PRG file. build_flags.asm is generated rather than committed so a
# stale switch cannot survive a checkout and silently ship the test policy.
$(OUT): src/*.asm
	@mkdir -p build
	@printf 'E2E_AUTOPLAY = 0\nSOLO_SELFTEST = 0\n' > $(FLAGS)
	$(ASM198X) --dialect acme --prg -I . --listing=build/report.txt $(SRC) -o $(OUT)
	@echo "Built: $(OUT)"

# Test build: the same client, driven by a deterministic move policy instead of
# the keyboard, so the harness can play a whole game against the real server.
e2e-prg:
	@mkdir -p build
	@printf 'E2E_AUTOPLAY = 1\nSOLO_SELFTEST = 0\n' > $(FLAGS)
	$(ASM198X) --dialect acme --prg -I . $(SRC) -o $(E2E_OUT)
	@printf 'E2E_AUTOPLAY = 0\nSOLO_SELFTEST = 0\n' > $(FLAGS)
	@echo "Built: $(E2E_OUT)"

# Kernel self-test: complete deterministic solo games under Emu198x, checking
# that each one ends and that all 52 cards survive it.
solo-selftest:
	@mkdir -p build
	@printf 'E2E_AUTOPLAY = 0\nSOLO_SELFTEST = 1\n' > $(FLAGS)
	$(ASM198X) --dialect acme --prg -I . --sym=build/solo-selftest.sym $(SRC) -o build/rachel-solo-selftest.prg
	@printf 'E2E_AUTOPLAY = 0\nSOLO_SELFTEST = 0\n' > $(FLAGS)
	python3 tests/solo_selftest.py

# Play a complete game against the Go server through the emulated user-port
# ESP-AT modem. Needs rachel-server and an Emu198x build.
e2e-full-game: e2e-prg
	python3 tests/full_game_e2e.py

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

test: $(OUT)
	python3 tests/test_transport.py

.PHONY: all test run test-net conformance reference-parity clean report \
	e2e-prg e2e-full-game solo-selftest
