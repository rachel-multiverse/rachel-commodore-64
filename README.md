# Rachel C64

[![C64 CI](https://github.com/rachel-multiverse/rachel-commodore-64/actions/workflows/ci.yml/badge.svg)](https://github.com/rachel-multiverse/rachel-commodore-64/actions/workflows/ci.yml)

Commodore 64 client for the Rachel card game, written in 6502 assembly.

Plays two ways. **Standalone** needs nothing but the machine: a local rules
kernel deals, enforces and plays the opponents, for the full 2-8 players the
rules define. **Online** connects to the Rachel server using RUBP (Rachel
Unified Binary Protocol); an enabled Ultimate Command Interface is detected
first, and a physical user-port WiFi modem is the fallback.

The two never mix. Online, the host is authoritative and the client renders
what it is told; the local kernel is not consulted about legality. That is the
line decision 0003 draws and decision 0006 leaves in place.

## Requirements

- [Asm198x](https://github.com/asm198x/asm198x)
- ACME Cross-Assembler (optional byte-parity oracle)
- [VICE Emulator](https://vice-emu.sourceforge.io/) (for testing)
- 1541 Ultimate-II or later with current network-capable firmware (preferred)
- Sven Petersen C64 WiFi Modem User Port Rev. 2 running Zimodem (fallback)

### macOS Installation

```bash
brew install asm198x/tap/asm198x acme vice
```

## Building

```bash
make               # Build rachel.prg
make test          # Build and verify both real-hardware transport contracts
make conformance   # Run RUBP codec checks under Emu198x
make solo-selftest # Play 16 complete solo games under Emu198x, 2-8 seats
make e2e-full-game # Play a networked game against the Go server
make clean         # Remove build artifacts
```

## Standalone play

Answer `S` at the opening prompt and pick a table size. The kernel deals from a
shuffled deck seeded off the jiffy clock and the raster, so no two games start
the same, and the opponents play by the same rules you do.

`make solo-selftest` plays sixteen complete games headlessly across every table
size and checks two things after each: that the game actually ended, and that
all 52 cards are still accounted for. The card count is what catches the family
of faults a card kernel is prone to — a draw that forgets to shrink the deck, a
recycle that duplicates the pile — which otherwise look perfectly plausible on
screen.

Runtime buffers live in free RAM at `$C100-$C3FF`; the KERNAL vectors and
cassette workspace in page `$03` are left untouched. All 32 possible hand
slots can be selected, and private hand state is reconciled through
`GAME_START`, `CARD_DRAWN`, and `HAND_SYNC`.

The client advertises `CAP_SYNC_ACK`, so the host holds `TURN_START` until the
client acknowledges the `GAME_STATE` + `HAND_SYNC` pair it was sent. Only a
`GAME_STATE` the client parsed itself can be acknowledged: the state hash rides
on several message types, and acknowledging one the client never received would
have it act a turn behind. Conformance covers that directly, against golden
fixtures whose `GAME_STATE` and `HAND_SYNC` carry deliberately different
hashes.

## Running in VICE

```bash
make run        # Launch in VICE (no network)
make test-net   # Launch with RS232->TCP bridge
```

For network testing, first start an iOS host or test server on port 19840.

## Hardware setup

### Ultimate-II, Ultimate-II+, Ultimate-II+L, Ultimate 64, or C64 Ultimate

1. Install current firmware and configure Ethernet or Wi-Fi.
2. Enable **Command Interface** in the Ultimate configuration.
3. Ensure `$DF1C-$DF1F` is not claimed by another enabled cartridge function.
4. Load and run `rachel.prg`, then enter `HOST:PORT`.

Rachel detects identification byte `$C9` and uses UCI Network Target `$03`
directly. It opens a TCP socket and transfers binary 64-byte messages through
the UCI queues; it does not use modem emulation or the C64 user port.

### User-port fallback

1. Connect a Sven Petersen C64 WiFi Modem User Port Rev. 2.
2. Install Zimodem and save a 2400-baud, 8N1, no-flow-control profile.
3. Load and run `rachel.prg`
4. Enter `HOST:PORT` when prompted.

The fallback uses the board wiring as published: C64 `PA2` transmits to the
modem and modem TXD is received on `PB0`/`FLAG2`, with the board providing the
required 3.3 V/5 V level conversion.

## Project Structure

```
src/
  main.asm      - Entry point, main loop
  ultimate.asm  - Ultimate Command Interface TCP implementation
  transport.asm - Runtime UCI/user-port selection
  serial.asm    - User Port serial fallback
  modem.asm     - AT command handling (Zimodem)
  rubp.asm      - RUBP message encoding/decoding
  screen.asm    - PETSCII screen rendering
  input.asm     - Keyboard input handling
  game.asm      - Game state management

build/
  rachel.prg    - Compiled C64 program
```

## Protocol

See the [RUBP Protocol Specification](https://github.com/rachel-multiverse/protocol/blob/main/PROTOCOL.md) for the binary protocol used for multiplayer communication.

## License

MIT
