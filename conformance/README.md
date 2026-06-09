# RUBP conformance

Offline checks that the C64 client's RUBP codec produces and reads bytes exactly
as the protocol specifies — **no networking, no emulator-of-the-server, no
running game required**. It runs the *real* client routines from `../src/rubp.asm`
on a real 6502 (under VICE) and diffs the bytes against the golden fixtures in
`rubp-messages-v1.json` — the same vectors the iOS reference and the Go server
validate against.

This isolates *codec correctness* from *networking*: if a message is built or
parsed wrong, it fails here in seconds, instead of being discovered mid-game in
VICE where you can't tell whether the codec or the serial path is at fault.

## Run it

```bash
cd conformance
python3 run.py
```

Requirements (both already used by this project): **acme** to assemble and
**x64sc** (VICE) on your `PATH`. `run.py` assembles the harness, boots it under
x64sc headless (`-console -warp`), drives the remote monitor to read back the
captured messages, and prints a per-message, per-byte verdict. Exit status is
non-zero if any **bug** or **unexplained** difference is present.

## What it covers

**Encoders** (`encoders.asm`) — the three messages the client builds: `HELLO`,
`PLAY_CARD`, `DRAW_CARD`. The harness drives each with the fixture's field values
and captures the 64-byte `SERIAL_TX_BUF` it produces, then diffs against the
golden vector. Each differing byte is classified:

| Status | Meaning |
|--------|---------|
| `OK-PLATFORM` | Legitimate platform-identity difference (C64 platform ID `0x0002` vs the fixture's iOS `0x0031`) — not a bug |
| `GAP` | A spec field the client deliberately does not emit (e.g. `reconnectToken` — see decision 0002) — documented |
| `BUG` | A field the client emits **incorrectly** — fails the run |
| `UNEXPECTED` | A difference with no explanation on file — fails the run |

The classifications live in the `KNOWN` table in `run.py`; an unexplained change
in the client's output surfaces as `UNEXPECTED` rather than slipping through.

**Decoders** (`decoders.asm`) — the two parsers with golden vectors:
`rubp_parse_welcome` and `rubp_parse_game_state`. The harness loads the golden
vector into `SERIAL_RX_BUF`, runs the parser, and captures every variable it
writes. `run.py` checks each against the same vector decoded at the **spec's**
offsets (an independent oracle from PROTOCOL.md) — so a parser reading the wrong
offset fails, rather than agreeing with a matching mistake. The input vectors are
generated into `build/vectors.inc` from the JSON each run, so there's no
hand-transcribed byte to drift. (`GAME_START`/`CARD_DRAWN` have no golden vector
in the fixture set, so they aren't covered here.)

## How it works

`run.py` runs the program to completion **before** connecting the remote monitor:
activating the monitor halts the CPU, so the harness must already have parked in
its final `jmp *` loop with results in the capture region (`$C000`+). The
encoders normally end by streaming `SERIAL_TX_BUF` out through `serial_send_byte`;
the harness stubs that (and `serial_recv_byte`) to `rts` so nothing touches the
User Port — the built message still sits in `SERIAL_TX_BUF`, which is what we copy
out.
