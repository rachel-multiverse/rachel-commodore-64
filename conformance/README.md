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

Currently the three messages the client **encodes**: `HELLO`, `PLAY_CARD`,
`DRAW_CARD`. The harness (`encoders.asm`) drives each encoder with the fixture's
field values and captures the 64-byte `SERIAL_TX_BUF` it builds. (Decoders —
`WELCOME`, `GAME_STATE`, `GAME_START`/`CARD_DRAWN` — are the next phase: preload
`SERIAL_RX_BUF` with a fixture and check the parsed-out variables.)

Each differing byte is classified:

| Status | Meaning |
|--------|---------|
| `OK-PLATFORM` | Legitimate platform-identity difference (e.g. C64 platform ID `0x0002` vs the fixture's iOS `0x0031`) — not a bug |
| `GAP` | A spec field the client does not yet emit (e.g. `specVersion`, `observedStateHash`) — documented, not yet conformant |
| `BUG` | A field the client emits **incorrectly** — fails the run |
| `UNEXPECTED` | A difference with no explanation on file — fails the run |

The classifications live in the `KNOWN` table in `run.py`; an unexplained change
in the client's output surfaces as `UNEXPECTED` rather than slipping through.

## How it works

`run.py` runs the program to completion **before** connecting the remote monitor:
activating the monitor halts the CPU, so the harness must already have parked in
its final `jmp *` loop with results in the capture region (`$C000`+). The
encoders normally end by streaming `SERIAL_TX_BUF` out through `serial_send_byte`;
the harness stubs that (and `serial_recv_byte`) to `rts` so nothing touches the
User Port — the built message still sits in `SERIAL_TX_BUF`, which is what we copy
out.
