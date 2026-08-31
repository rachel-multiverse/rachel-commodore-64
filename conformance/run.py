#!/usr/bin/env python3
"""RUBP codec conformance for the C64 client.

Runs the real client codec from src/rubp.asm on a real C64 under Emu198x
(emu198x-c64, headless) and checks it against the golden fixtures in
rubp-messages-v1.json — the same vectors the iOS reference and the Go server
validate against. No networking, no running game.

Two phases:

  Encoders — drive HELLO / PLAY_CARD / DRAW_CARD with the fixture's field values
    and diff the 64-byte message each builds against its golden vector. Differing
    bytes are classified OK-PLATFORM / OK-CAPABILITY / GAP / BUG / UNEXPECTED.

  Decoders — feed the golden WELCOME / GAME_STATE vectors into the parsers and
    check each extracted value against the same vector decoded at the spec's
    offsets (an independent oracle: a parser reading the wrong offset fails).

Exit status is non-zero on any BUG / UNEXPECTED / decoder mismatch.

Usage:  python3 run.py
Needs: asm198x, and emu198x-c64 (set EMU198X_C64, or it defaults to
       ~/Projects/198x/Emu198x/emu198x/target/debug/emu198x-c64).
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
FIXTURES = os.path.join(HERE, "rubp-messages-v1.json")
FIXTURES_SHA = os.path.join(HERE, "rubp-messages-v1.sha256")
EMU = os.environ.get(
    "EMU198X_C64",
    os.path.expanduser("~/Projects/198x/Emu198x/emu198x/target/debug/emu198x-c64"),
)
ASM198X = os.environ.get("ASM198X", "asm198x")

# ---- Encoder harness (encoders.asm) -----------------------------------------
ENC_PRG = os.path.join(BUILD, "encoders.prg")
ENC_SLOTS = {"hello": 0xC000, "play_card": 0xC040, "draw_card": 0xC080}
ENC_DONE = 0xC0FF

# Per-message, per-offset explanations for known differences from the golden
# vectors. Anything that differs and is NOT listed here is reported UNEXPECTED.
KNOWN = {
    "hello": {
        33: ("OK-PLATFORM", "platform ID 0x0002 (C64) vs fixture's 0x0031 (iOS)"),
        # specVersion (34/35) is now emitted; reconnectToken stays a gap — this
        # client does not reclaim slots, so it sends a zero token (decision 0002).
        **{o: ("GAP", "reconnectToken not emitted (no reconnect support)") for o in range(36, 44)},
        # Capabilities (payload+36). We advertise CAP_SYNC_ACK so the host holds
        # TURN_START until we acknowledge the GAME_STATE + HAND_SYNC pair; the
        # iOS fixture does not negotiate it, being a client that can buffer
        # consecutive frames. Advertising more than the fixture is conformant.
        52: ("OK-CAPABILITY", "advertises CAP_SYNC_ACK; fixture client does not"),
    },
    "play_card": {},
    "draw_card": {},
}
FAIL_STATUSES = {"BUG", "UNEXPECTED"}

# ---- Decoder harness (decoders.asm) -----------------------------------------
DEC_PRG = os.path.join(BUILD, "decoders.prg")
DEC_SLOTS = {"welcome": (0xC000, 6), "game_state": (0xC010, 25), "sync_ack": (0xC030, 15)}
DEC_DONE = 0xC0FF
CONN_WAITING = 3  # rubp_parse_welcome sets this


def run(cmd):
    return subprocess.run(cmd, cwd=HERE, check=True)


def assemble(src, prg):
    os.makedirs(BUILD, exist_ok=True)
    run([ASM198X, "--dialect", "acme", "--prg", "-I", "..", "-I", ".",
         src, "-o", prg])


def capture(prg, regions, done_addr):
    """Run a harness PRG under emu198x-c64 and read back memory regions.

    regions: {name: (addr, length)}. Returns {name: [bytes]}.

    The harness is a BASIC-stub PRG: --load imports it, the script types RUN to
    SYS into the machine code (the C64 keyboard scan needs a key held across a
    few frames, hence the press / run / release rhythm), it runs every test into
    the capture region and parks, and memory_read pulls each region back.
    """
    if not os.path.exists(EMU):
        sys.exit(f"emu198x-c64 not found at {EMU}\n"
                 f"build it: cargo build -p emu198x-c64 --no-default-features")
    steps = [{"action": "wait_for_boot", "max_frames": 400}]
    for key in ("r", "u", "n", "return"):
        steps += [
            {"action": "input", "events": [{"Key": {"name": key, "pressed": True}}]},
            {"action": "run_frames", "frames": 4},
            {"action": "input", "events": [{"Key": {"name": key, "pressed": False}}]},
            {"action": "run_frames", "frames": 4},
        ]
    steps.append({"action": "run_frames", "frames": 60})
    steps.append({"action": "memory_read", "addr": done_addr, "len": 1})
    for addr, length in regions.values():
        steps.append({"action": "memory_read", "addr": addr, "len": length})

    script = os.path.join(BUILD, "session.json")
    with open(script, "w") as f:
        json.dump(steps, f)

    out = subprocess.run(
        [EMU, "--headless", "--load", prg, "--script", script],
        cwd=HERE, check=True, capture_output=True, text=True,
    ).stdout
    reads = {}
    for o in json.loads(out).get("observations", []):
        if o.get("kind") == "memory_read":
            reads[o["addr"]] = bytes(o["bytes"])

    if reads.get(done_addr, b"\0")[:1] != b"\xaa":
        raise RuntimeError("harness did not finish (done marker not set) — try more run_frames")
    return {name: list(reads[addr]) for name, (addr, _length) in regions.items()}


def golden(fixtures, name):
    for m in fixtures["messages"]:
        if m["name"] == name:
            return bytes.fromhex(m["hex"])
    raise KeyError(name)


# -----------------------------------------------------------------------------
# Encoder phase
# -----------------------------------------------------------------------------
def check_encoders(fixtures):
    assemble("encoders.asm", ENC_PRG)
    got = capture(ENC_PRG, {n: (a, 64) for n, a in ENC_SLOTS.items()}, ENC_DONE)

    print("ENCODERS — message the client builds vs golden vector\n")
    failed = False
    for name in ENC_SLOTS:
        produced, gold = bytes(got[name]), golden(fixtures, name)
        known = KNOWN.get(name, {})
        diffs = [i for i in range(64) if produced[i] != gold[i]]
        statuses = [(i, *known.get(i, ("UNEXPECTED", "no explanation on file"))) for i in diffs]
        bug = any(s in FAIL_STATUSES for _, s, _ in statuses)
        failed = failed or bug
        verdict = "CONFORMANT" if not diffs else ("FAIL" if bug else "conformant (documented gaps only)")
        print(f"== {name:<10} {verdict} ==")
        if not diffs:
            print("   byte-for-byte match\n")
            continue
        for i, status, note in statuses:
            print(f"   @{i:2d}  C64={produced[i]:02x} golden={gold[i]:02x}  [{status}] {note}")
        print()
    return failed


# -----------------------------------------------------------------------------
# Decoder phase
# -----------------------------------------------------------------------------
def emit_byte_table(label, data):
    lines = [f"{label}:"]
    for i in range(0, len(data), 16):
        lines.append("        !byte " + ", ".join(f"${b:02x}" for b in data[i:i + 16]))
    return "\n".join(lines)


def gen_vectors_inc(fixtures):
    os.makedirs(BUILD, exist_ok=True)
    body = [
        "; Generated by run.py from rubp-messages-v1.json — do not edit.",
        emit_byte_table("welcome_msg", golden(fixtures, "welcome")),
        emit_byte_table("game_state_msg", golden(fixtures, "game_state")),
        emit_byte_table("hand_sync_msg", golden(fixtures, "hand_sync")),
        "",
    ]
    with open(os.path.join(BUILD, "vectors.inc"), "w") as f:
        f.write("\n".join(body))


def u16be(b, off):
    return (b[off] << 8) | b[off + 1]


def check_decoders(fixtures):
    gen_vectors_inc(fixtures)
    assemble("decoders.asm", DEC_PRG)
    got = capture(DEC_PRG, DEC_SLOTS, DEC_DONE)

    w = golden(fixtures, "welcome")
    wp = w[16:]   # WELCOME payload
    wc = got["welcome"]
    # Expected values decoded from the golden vector at the SPEC's offsets.
    welcome_checks = [
        ("assignedPlayerID", wc[0] | (wc[1] << 8), u16be(wp, 0)),
        ("gameID",           wc[2] | (wc[3] << 8), u16be(wp, 2)),
        ("playerCount",      wc[4],                wp[4]),
        ("connState=WAITING", wc[5],               CONN_WAITING),
    ]

    g = golden(fixtures, "game_state")
    gp = g[16:]   # GAME_STATE payload
    gc = got["game_state"]
    gs_checks = [
        ("currentPlayer", gc[0], gp[0]),
        ("direction",     gc[1], gp[1]),
        ("topCard",       gc[2], gp[2]),
        ("nominatedSuit", gc[3], gp[3]),
        ("pendingDraws",  gc[4], gp[4]),
        ("deckCount",     gc[5], gp[6]),
    ]
    for i in range(8):
        gs_checks.append((f"playerCount[{i}]", gc[6 + i], gp[7 + i]))
    gs_checks += [
        ("isGameOver",  gc[14], gp[15]),
        ("winnerIndex", gc[15], gp[16]),
    ]
    for i in range(8):
        gs_checks.append((f"stateHash[{i}]", gc[16 + i], gp[24 + i]))
    gs_checks.append(("hashValid", gc[24], 1 if (gp[23] & 0x01) else 0))

    # The acknowledgement must describe the GAME_STATE the client actually
    # parsed, not the HAND_SYNC that completed the pair. Both carry a state
    # hash and the fixtures carry different ones, so echoing the wrong message
    # is directly visible here. See CLIENT_GUIDE.md, "Acknowledge what you
    # received, not what you were told".
    h = golden(fixtures, "hand_sync")
    hp = h[16:]   # HAND_SYNC payload: TurnNumber @33, SpecVersion @37, hash @40
    sc = got["sync_ack"]
    sync_checks = [("flags=hash|ack", sc[0], 0x03)]
    for i in range(4):
        sync_checks.append((f"turnNumber[{i}]", sc[1 + i], gp[17 + i]))
    for i in range(2):
        sync_checks.append((f"specVersion[{i}]", sc[5 + i], gp[21 + i]))
    for i in range(8):
        sync_checks.append((f"stateHash[{i}]", sc[7 + i], gp[24 + i]))
    # Belt and braces: state it as the negative too, so the intent survives
    # someone later "fixing" the offsets to agree with the wrong message.
    sync_checks.append((
        "hash is not HAND_SYNC's",
        0 if bytes(sc[7:15]) == bytes(hp[40:48]) else 1,
        1,
    ))
    sync_checks.append((
        "turn is not HAND_SYNC's",
        0 if bytes(sc[1:5]) == bytes(hp[33:37]) else 1,
        1,
    ))

    print("DECODERS — value the parser extracted vs golden vector at spec offsets\n")
    failed = False
    for name, checks in [("welcome", welcome_checks), ("game_state", gs_checks),
                         ("sync_ack", sync_checks)]:
        bad = [(label, got_v, want_v) for label, got_v, want_v in checks if got_v != want_v]
        failed = failed or bool(bad)
        print(f"== {name:<10} {'PASS' if not bad else 'FAIL'} ==")
        if bad:
            for label, got_v, want_v in bad:
                print(f"   {label:<18} got={got_v:#04x} want={want_v:#04x}")
        else:
            print(f"   all {len(checks)} fields extracted correctly")
        print()
    return failed


def check_fixtures_pinned():
    """Refuse to run against vectors that no longer match the ones we pinned.

    The vectors are vendored rather than fetched, because this harness runs
    offline by design and a fresh clone has to work without a network. The
    price of vendoring is a copy that can quietly stop matching its source -
    four copies of this file exist across the project - so the hash beside it
    is checked before anything else.

    This catches local edits. It cannot tell you the *upstream* file has moved
    on; no offline check can. `./refresh-vectors.sh` is how you find that out.
    """
    if not os.path.exists(FIXTURES_SHA):
        return
    want = open(FIXTURES_SHA).read().split()[0]
    got = hashlib.sha256(open(FIXTURES, "rb").read()).hexdigest()
    if got != want:
        print("FIXTURES DO NOT MATCH THE PINNED HASH", file=sys.stderr)
        print(f"  expected {want}", file=sys.stderr)
        print(f"  found    {got}", file=sys.stderr)
        print("", file=sys.stderr)
        print("rubp-messages-v1.json has been edited since it was pinned.", file=sys.stderr)
        print("These vectors are shared - the canonical copy lives at", file=sys.stderr)
        print("  https://github.com/rachel-multiverse/protocol", file=sys.stderr)
        print("Run ./refresh-vectors.sh to pull it and re-pin, or restore the", file=sys.stderr)
        print("file. Do not edit it here: a client's private idea of the wire", file=sys.stderr)
        print("format is the one bug this harness cannot catch.", file=sys.stderr)
        sys.exit(2)


def main():
    check_fixtures_pinned()
    fixtures = json.load(open(FIXTURES))
    print(f"RUBP codec conformance — C64 client vs {fixtures['fixture']}\n")
    if "--assemble-only" in sys.argv:
        gen_vectors_inc(fixtures)
        assemble("encoders.asm", ENC_PRG)
        assemble("decoders.asm", DEC_PRG)
        print("RESULT: conformance harnesses assembled successfully (emulator run skipped).")
        return
    failed = check_encoders(fixtures)
    failed |= check_decoders(fixtures)
    if failed:
        print("RESULT: failures present — see FAIL / [BUG] / [UNEXPECTED] above.")
        sys.exit(1)
    print("RESULT: encoders conformant (platform/gaps only); decoders extract every field correctly.")


if __name__ == "__main__":
    main()
