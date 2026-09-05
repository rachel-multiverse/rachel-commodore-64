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

## Verification status

This is a development build. See [the verification record](docs/STATUS.md) for
checks run against this revision and the remaining hardware limitations. Solo
play needs no network hardware or server. There is currently no public server
for online play.

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
make ui-test       # Check rendering, keyboard actions, Ace prompts and results
make production-ui-test # Exercise the real menu and solo keyboard controls
make solo-selftest # Play 16 complete solo games under Emu198x, 2-8 seats
make e2e-full-game # Play a networked game against the Go server
make reconnect-test # Verify recovery ordering, rejection and retry/menu behaviour
make reconnect-e2e  # Drop two live connections and verify the restored seat/hand
make clean         # Remove build artifacts
```

## Standalone play

Answer `S` at the opening prompt and pick a table size. The kernel deals from a
shuffled deck seeded off the jiffy clock and the raster, to vary the deal between games, and the opponents play by the same rules you do.

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

## Reconnecting

During an online game, the client retries a dropped connection automatically.
It retains the server address and session token in RAM, then asks the server to
restore the same seat. Input stays paused until the table and private hand have
been refreshed. Selected cards are cleared; an interrupted move is never replayed.

After three unsuccessful attempts, press `R` to retry or `Q` for the menu.
Returning to the menu, resetting or reloading starts a new session and discards
the token. If the server has taken over a disconnected seat with AI, its current
hand is restored. A stopped/restarted server cannot restore an in-memory game.

Ultimate reports a closed socket directly. The user-port fallback uses a silence
timeout and Hayes escape/redial. For the 2400-baud modem, run the Go server
with `serve --vic20-write-interval 300ms`; despite its name, this spacing
option also applies to C64 serial clients. `make reconnect-userport-e2e` tests
that configuration. An unpaced serial run reclaimed both drops but stalled
later, so unpaced modem operation is not verified. See `docs/STATUS.md` for transport-specific
verification; physical hardware is still unverified.

## Running in VICE

```bash
make run        # Launch in VICE (no network)
make test-net   # Launch with RS232->TCP bridge
```

The legacy VICE bridge target connects to localhost:19840. Run a compatible
Rachel server on that port for this target; the normal server default and the
end-to-end harness use port 6502. An App Store iOS installation is not a
public vintage game server.

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
