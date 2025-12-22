# Rachel C64

Commodore 64 client for the Rachel card game, written in 6502 assembly.

Connects to an iOS/macOS host via WiFi bridge using the RUBP (Rachel Unified Binary Protocol).

## Requirements

- [ACME Cross-Assembler](https://sourceforge.net/projects/acme-crossass/)
- [VICE Emulator](https://vice-emu.sourceforge.io/) (for testing)
- Zimodem-compatible WiFi modem (for real hardware)

### macOS Installation

```bash
brew install acme vice
```

## Building

```bash
make            # Build rachel.prg
make clean      # Remove build artifacts
```

## Running in VICE

```bash
make run        # Launch in VICE (no network)
make test-net   # Launch with RS232->TCP bridge
```

For network testing, first start an iOS host or test server on port 19840.

## Hardware Setup

For real C64 hardware:

1. Connect Zimodem to User Port
2. Configure for 2400 baud, 8N1
3. Load and run `rachel.prg`
4. Enter host IP address when prompted

## Project Structure

```
src/
  main.asm      - Entry point, main loop
  serial.asm    - User Port serial I/O
  modem.asm     - AT command handling (Zimodem)
  rubp.asm      - RUBP message encoding/decoding
  screen.asm    - PETSCII screen rendering
  input.asm     - Keyboard input handling
  game.asm      - Game state management

build/
  rachel.prg    - Compiled C64 program
```

## Protocol

See [RUBP Protocol Specification](../docs/PROTOCOL.md) for the binary protocol used for multiplayer communication.

## License

MIT
