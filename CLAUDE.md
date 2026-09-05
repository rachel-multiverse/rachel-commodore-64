# CLAUDE.md - Rachel C64 Client

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Rachel C64 is a Commodore 64 client for the Rachel card game, written in ACME-compatible 6502 assembly and built with Asm198x. It supports standalone play through a local rules kernel and online play against a compatible Rachel server through Ultimate networking or a user-port WiFi modem.

## Build Commands

```bash
make            # Build rachel.prg
make run        # Run in VICE emulator
make test-net   # Run with RS232->TCP bridge to localhost:19840
make clean      # Clean build artifacts
```

## Architecture

Standalone mode runs the rules and computer opponents locally in `src/solo.asm`.
Online mode remains a render-only client: the server owns legality and game
state; the local kernel does not participate. See `docs/STATUS.md` for verified
behaviour and outstanding hardware checks.

## Hardware Constraints

- **CPU:** 6502 @ 1MHz
- **Serial:** User Port @ 2400 baud (via Zimodem)
- **Display:** 40x25 PETSCII text mode
- **Memory:** Standard BASIC area ($0801+)

## File Structure

| File | Purpose |
|------|---------|
| `src/main.asm` | Entry point, main loop, initialization |
| `src/serial.asm` | User Port serial I/O (2400,8,N,1) |
| `src/modem.asm` | Zimodem AT command handling |
| `src/rubp.asm` | RUBP 64-byte message encoding/decoding |
| `src/screen.asm` | PETSCII screen rendering |
| `src/input.asm` | Keyboard scanning and input |
| `src/game.asm` | Game state, hand management |

## ACME-compatible Asm198x Notes

- No powerful macros - explicit code is intentional
- Use `!byte`, `!word`, `!text` for data
- Labels are global by default, use `.local` for local labels
- Big-endian for RUBP protocol (network byte order)

## Memory Map

```
$0000-$00FF  Zero page variables
$0100-$01FF  Stack
$0200-$023F  Serial RX buffer (64 bytes)
$0240-$027F  Serial TX buffer (64 bytes)
$0280-$02FF  AT command buffer
$0300-$03FF  Game state variables
$0400-$07FF  Screen RAM
$0801+       Program code
$D000-$DFFF  I/O (VIC-II, CIA)
```

## Key Addresses

| Address | Purpose |
|---------|---------|
| $DD00 | CIA2 Port A (User Port data) |
| $DD01 | CIA2 Port B |
| $DD0D | CIA2 Interrupt Control |
| $DD0E | CIA2 Timer A Control |
| $DD0F | CIA2 Timer B Control |

## Testing with VICE

The `make test-net` command bridges VICE's RS232 emulation to TCP:
```bash
x64sc -rsuser -rsuserbaud 2400 -rsuserdev 2 -rsdev2 "|nc localhost 19840" build/rachel.prg
```

This legacy target connects to a compatible local server on port 19840. The normal server and `make e2e-full-game` use port 6502.

## Related Documentation

- `../protocol/PROTOCOL.md` - canonical RUBP binary protocol specification
- `../docs/GAME_RULES.md` - Rachel card game rules
- `../rachel-ios/docs/plans/2025-12-22-rachel-c64-design.md` - Design document
