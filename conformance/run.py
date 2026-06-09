#!/usr/bin/env python3
"""RUBP encoder conformance for the C64 client.

Assembles the real client encoders (src/rubp.asm) inside a tiny harness, runs
them on a real 6502 under VICE (x64sc, headless via the remote monitor), reads
back the 64-byte messages they produced, and diffs each against the golden
fixtures in rubp-messages-v1.json — the same vectors the iOS reference and the
Go server validate against.

Each differing byte is classified:
  OK-PLATFORM  legitimate platform identity difference (not a bug)
  GAP          a spec field the client does not yet emit (documented)
  BUG          a field the client emits incorrectly
  UNEXPECTED   a difference with no explanation -> fails the run

Exit status is non-zero if any BUG or UNEXPECTED difference is present, so this
can gate changes once the gaps are resolved or explicitly waived.

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
PRG = os.path.join(HERE, "build", "encoders.prg")
FIXTURES = os.path.join(HERE, "rubp-messages-v1.json")
MON_PORT = 6510

# Capture addresses must match encoders.asm.
SLOTS = {"hello": 0xC000, "play_card": 0xC040, "draw_card": 0xC080}
DONE_MARKER = 0xC0FF

# Per-message, per-offset explanations for known differences from the golden
# vectors. Offsets are absolute within the 64-byte message. Anything that
# differs and is NOT listed here is reported as UNEXPECTED.
KNOWN = {
    "hello": {
        33: ("OK-PLATFORM", "platform ID 0x0002 (C64) vs fixture's 0x0031 (iOS)"),
        # specVersion (34/35) is now emitted; reconnectToken stays a gap — this
        # client does not reclaim slots, so it sends a zero token.
        **{o: ("GAP", "reconnectToken not emitted (no reconnect support)") for o in range(36, 44)},
    },
    # play_card and draw_card now emit specVersion + the ObservedStateHash the
    # client captured from the last GAME_STATE, so they match byte-for-byte.
    "play_card": {},
    "draw_card": {},
}

FAIL_STATUSES = {"BUG", "UNEXPECTED"}


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=HERE, check=True, **kw)


def assemble():
    os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
    run(["acme", "-f", "cbm", "-o", PRG, "encoders.asm"])


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


def capture(boot_delay=6.0):
    """Run the harness under x64sc and read back the capture region.

    The harness autostarts and runs straight through to an infinite loop, leaving
    its results in the capture region. We must let it finish BEFORE connecting:
    activating the remote monitor halts the CPU, so we can only read the parked
    result, not step the program forward. Hence the boot delay (warp mode keeps
    it short in wall-clock terms).
    """
    subprocess.run(["pkill", "-f", "x64sc"], cwd=HERE)
    time.sleep(0.3)
    emu = subprocess.Popen(
        ["x64sc", "-console", "-warp", "-remotemonitor",
         "-remotemonitoraddress", f"ip4://127.0.0.1:{MON_PORT}",
         "-autostart", PRG],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(boot_delay)  # let autostart + the harness run to completion
        sock = None
        for _ in range(10):
            try:
                sock = socket.create_connection(("127.0.0.1", MON_PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.5)
        if sock is None:
            raise RuntimeError("could not reach x64sc remote monitor")
        marker = parse_mem(mon(sock, f"m {DONE_MARKER:04x} {DONE_MARKER:04x}"))[:1]
        if marker != [0xAA]:
            raise RuntimeError(
                f"harness did not finish (done marker={marker}); "
                f"try a longer boot_delay")
        out = {}
        for name, addr in SLOTS.items():
            out[name] = parse_mem(mon(sock, f"m {addr:04x} {addr + 63:04x}"))[:64]
        mon(sock, "quit")
        return out
    finally:
        emu.terminate()
        subprocess.run(["pkill", "-f", "x64sc"], cwd=HERE)


def golden_bytes(fixtures, name):
    for m in fixtures["messages"]:
        if m["name"] == name:
            return bytes.fromhex(m["hex"])
    raise KeyError(name)


def main():
    fixtures = json.load(open(FIXTURES))
    assemble()
    got = capture()

    overall_fail = False
    print(f"RUBP encoder conformance — C64 client vs {fixtures['fixture']}\n")
    for name in SLOTS:
        produced = bytes(got[name])
        gold = golden_bytes(fixtures, name)
        known = KNOWN.get(name, {})
        diffs = [i for i in range(64) if produced[i] != gold[i]]

        statuses = []
        for i in diffs:
            status, note = known.get(i, ("UNEXPECTED", "no explanation on file"))
            statuses.append((i, status, note))

        bug = any(s in FAIL_STATUSES for _, s, _ in statuses)
        overall_fail = overall_fail or bug
        if not diffs:
            verdict = "CONFORMANT"
        elif bug:
            verdict = "FAIL"
        else:
            verdict = "conformant (documented gaps only)"
        print(f"== {name:<10} {verdict} ==")
        if not diffs:
            print("   byte-for-byte match\n")
            continue
        # Collapse contiguous same-status runs for readable output.
        for i, status, note in statuses:
            print(f"   @{i:2d}  C64={produced[i]:02x} golden={gold[i]:02x}  [{status}] {note}")
        print()

    if overall_fail:
        print("RESULT: bugs/unexpected differences present — see [BUG]/[UNEXPECTED] above.")
        sys.exit(1)
    print("RESULT: no bugs; differences are platform identity or documented gaps.")


if __name__ == "__main__":
    main()
