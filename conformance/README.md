# RUBP conformance

Offline checks that the C64 client's RUBP codec produces and reads bytes exactly
as the protocol specifies — **no networking, no emulator-of-the-server, no
running game required**. It runs the *real* client routines from `../src/rubp.asm`
on a real C64 (under Emu198x, headless) and diffs the bytes against the golden
fixtures in `rubp-messages-v1.json`.

Those vectors are shared, and the canonical copy lives in
[rachel-multiverse/protocol](https://github.com/rachel-multiverse/protocol).
They are vendored here rather than fetched, so this stays runnable offline —
and pinned in `rubp-messages-v1.sha256`, which `run.py` checks before it does
anything else. Edit the JSON and the harness refuses to run; the fix is
`./refresh-vectors.sh`, not a local edit. A client's private idea of the wire
format is the one bug this harness cannot catch.

This isolates *codec correctness* from *networking*: if a message is built or
parsed wrong, it fails here in seconds, instead of being discovered mid-game
where you can't tell whether the codec or the serial path is at fault.

## Run it

```bash
cd conformance
python3 run.py
```

Requirements:

- **acme** (the client's own assembler) on your `PATH`.
- **emu198x-c64**, the headless C64 runner from the Emu198x project. Build it
  once with `cargo build -p emu198x-c64 --no-default-features`, then either put
  it on `PATH` or point `EMU198X_C64` at the binary. The default is
  `~/Projects/198x/Emu198x/target/debug/emu198x-c64`. It auto-discovers the C64
  ROMs from `~/.emu198x/roms/commodore-c64`.

`run.py` assembles each harness PRG (`acme`), `--load`s it under Emu198x headless,
types `RUN` to start it, `memory_read`s the capture region back as JSON, and
prints a per-message, per-byte verdict. Exit status is non-zero if any **bug** or
**unexplained** difference is present. (This is the same `memory_read` /
golden-fixture pattern the ZX Spectrum harness uses — only the assembler and the
Emu198x binary differ.)

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

Each harness is a BASIC-stub PRG. `run.py` `--load`s it, types `RUN` (the C64
keyboard scan needs each key held across a few frames, hence the press/run/release
rhythm in the script), and the stub `SYS`es into the machine code, which runs
every test into the capture region (`$C000`+), sets a done marker, and parks in
its `jmp *` loop. `memory_read` then pulls each region back. The encoders normally
end by streaming `SERIAL_TX_BUF` out through `serial_send_byte`; the harness stubs
that (and `serial_recv_byte`) to `rts` so nothing touches the User Port — the
built message still sits in `SERIAL_TX_BUF`, which is what we read.
