#!/usr/bin/env python3
"""RUBP codec conformance for the C64 client.

Runs the real client codec from src/rubp.asm on a real 6502 under VICE (x64sc,
headless via the remote monitor) and checks it against the golden fixtures in
rubp-messages-v1.json — the same vectors the iOS reference and the Go server
validate against. No networking, no running game.

Two phases:

  Encoders — drive HELLO / PLAY_CARD / DRAW_CARD with the fixture's field values
    and diff the 64-byte message each builds against its golden vector. Differing
    bytes are classified OK-PLATFORM / GAP / BUG / UNEXPECTED.

  Decoders — feed the golden WELCOME / GAME_STATE vectors into the parsers and
    check each extracted value against the same vector decoded at the spec's
    offsets (an independent oracle: a parser reading the wrong offset fails).

Exit status is non-zero on any BUG / UNEXPECTED / decoder mismatch.

Usage:  python3 run.py            (needs: acme, x64sc on PATH)
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
FIXTURES = os.path.join(HERE, "rubp-messages-v1.json")
MON_PORT = 6510

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
    },
    "play_card": {},
    "draw_card": {},
}
FAIL_STATUSES = {"BUG", "UNEXPECTED"}

# ---- Decoder harness (decoders.asm) -----------------------------------------
DEC_PRG = os.path.join(BUILD, "decoders.prg")
DEC_SLOTS = {"welcome": (0xC000, 6), "game_state": (0xC010, 25)}
DEC_DONE = 0xC0FF
CONN_WAITING = 3  # rubp_parse_welcome sets this


def run(cmd):
    return subprocess.run(cmd, cwd=HERE, check=True)


def assemble(src, prg):
    os.makedirs(BUILD, exist_ok=True)
    run(["acme", "-f", "cbm", "-o", prg, src])


def mon(sock, line):
    try:
        sock.sendall((line + "\n").encode())
    except OSError:
        return ""
    time.sleep(0.2)
    out = b""
    sock.settimeout(1.5)
    try:
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                break
            out += chunk
    except (socket.timeout, OSError):
        pass
    return out.decode(errors="replace")


def parse_mem(text):
    by = []
    for line in text.splitlines():
        m = re.search(r"C:[0-9a-fA-F]{4}\s+((?:[0-9a-fA-F]{2}\s+)+)", line)
        if m:
            by += [int(x, 16) for x in m.group(1).split()]
    return by


def capture(prg, regions, done_addr, boot_delay=6.0):
    """Run a harness PRG under x64sc and read back memory regions.

    regions: {name: (addr, length)}. Returns {name: [bytes]}.

    The harness must run to completion BEFORE we connect — activating the remote
    monitor halts the CPU, so we read the parked result, not step it forward.
    """
    subprocess.run(["pkill", "-f", "x64sc"], cwd=HERE)
    time.sleep(0.3)
    emu = subprocess.Popen(
        ["x64sc", "-console", "-warp", "-remotemonitor",
         "-remotemonitoraddress", f"ip4://127.0.0.1:{MON_PORT}",
         "-autostart", prg],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(boot_delay)
        sock = None
        for _ in range(10):
            try:
                sock = socket.create_connection(("127.0.0.1", MON_PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.5)
        if sock is None:
            raise RuntimeError("could not reach x64sc remote monitor")
        if parse_mem(mon(sock, f"m {done_addr:04x} {done_addr:04x}"))[:1] != [0xAA]:
            raise RuntimeError("harness did not finish (try a longer boot_delay)")
        out = {}
        for name, (addr, length) in regions.items():
            out[name] = parse_mem(mon(sock, f"m {addr:04x} {addr + length - 1:04x}"))[:length]
        mon(sock, "quit")
        return out
    finally:
        emu.terminate()
        subprocess.run(["pkill", "-f", "x64sc"], cwd=HERE)


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

    print("DECODERS — value the parser extracted vs golden vector at spec offsets\n")
    failed = False
    for name, checks in [("welcome", welcome_checks), ("game_state", gs_checks)]:
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


def main():
    fixtures = json.load(open(FIXTURES))
    print(f"RUBP codec conformance — C64 client vs {fixtures['fixture']}\n")
    failed = check_encoders(fixtures)
    failed |= check_decoders(fixtures)
    if failed:
        print("RESULT: failures present — see FAIL / [BUG] / [UNEXPECTED] above.")
        sys.exit(1)
    print("RESULT: encoders conformant (platform/gaps only); decoders extract every field correctly.")


if __name__ == "__main__":
    main()
