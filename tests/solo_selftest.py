#!/usr/bin/env python3
"""Play complete solo games inside Emu198x and check the kernel's invariants.

The client build under test drives every seat from the kernel's own policy, so
a whole game runs with no input. Two things are checked per game: that it ended
at all, and that all 52 cards are still accounted for afterwards. The card
count is what catches a draw that forgets to shrink the deck or a recycle that
duplicates the pile — faults that look perfectly plausible on screen.
"""

from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EMU = Path(os.environ.get("EMU198X_DIR", Path.home() / "Projects/198x/Emu198x/emu198x"))
EMU_BIN = EMU / "target/release/emu198x-c64"
ROMS = Path(os.environ.get("C64_ROM_DIR", Path.home() / ".emu198x/roms/commodore-c64"))
PRG = ROOT / "build/rachel-solo-selftest.prg"
SYM = ROOT / "build/solo-selftest.sym"
FRAMES = int(os.environ.get("RACHEL_SOLO_FRAMES", "6000"))
EXPECTED_GAMES = 16


def symbol(table: str, name: str) -> int:
    match = re.search(rf"^{name}\s*=\s*\$([0-9A-Fa-f]+)", table, re.MULTILINE)
    if not match:
        raise SystemExit(f"{name} missing from {SYM}")
    return int(match.group(1), 16)


def main() -> None:
    if not EMU_BIN.is_file():
        raise SystemExit(
            f"{EMU_BIN} not found; build it with "
            f"`cargo build --release -p emu198x-c64` in {EMU}"
        )
    if not PRG.is_file():
        raise SystemExit(f"{PRG} not found; run `make solo-selftest`")

    table = SYM.read_text()
    counters = {
        name: symbol(table, name)
        for name in ("solo_test_passed", "solo_test_failed",
                     "solo_test_bounded", "solo_test_game",
                     "solo_test_last_count")
    }

    session = ROOT / "build/solo-selftest.json"
    session.write_text(json.dumps([
        {"action": "run_frames", "frames": 200},
        {"action": "type_string", "text": "RUN\n", "hold_frames": 2,
         "settle_frames": 40},
        {"action": "run_frames", "frames": FRAMES},
        *({"action": "memory_read", "addr": addr, "len": 1}
          for addr in counters.values()),
    ], indent=2) + "\n")

    result = subprocess.run([
        str(EMU_BIN), "--headless", "--rom-dir", str(ROMS),
        "--load", str(PRG), "--script", str(session),
    ], cwd=EMU, text=True, capture_output=True, timeout=600)
    if result.returncode:
        raise SystemExit(f"emulator failed:\n{result.stdout}\n{result.stderr}")

    report = json.loads(result.stdout)
    reads = [item["bytes"][0] for item in report["observations"]
             if item["kind"] == "memory_read"]
    values = dict(zip(counters, reads))

    played = values["solo_test_game"]
    if played != EXPECTED_GAMES:
        raise SystemExit(
            f"only {played} of {EXPECTED_GAMES} games ran in {FRAMES} frames; "
            f"raise RACHEL_SOLO_FRAMES. {values}"
        )
    if values["solo_test_failed"]:
        raise SystemExit(f"cards went missing or were duplicated: {values}")
    if values["solo_test_bounded"]:
        raise SystemExit(f"a game never ended within the turn bound: {values}")
    if values["solo_test_passed"] != EXPECTED_GAMES:
        raise SystemExit(f"unexpected counter state: {values}")

    print(f"Solo kernel self-test passed: {EXPECTED_GAMES} complete games, "
          f"2-8 seats, all 52 cards accounted for in each")


if __name__ == "__main__":
    try:
        main()
    except subprocess.TimeoutExpired as error:
        print(f"timed out: {error}", file=sys.stderr)
        raise SystemExit(1)
