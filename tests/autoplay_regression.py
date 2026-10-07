"""Check the real test-only move policy and encoders against Rachel's rules."""

from __future__ import annotations

import binascii
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/autoplay-regression"
# name, hand, discard, nomination, draws, skips, expected card (None = draw), suit
CASES = [
    ("ace_not_wild", [0x0E, 0x85], 0x83, 255, 0, 0, 0x85, 255),
    ("unmatched_ace_draws", [0x0E], 0x83, 255, 0, 0, None, 255),
    ("ace_matches_suit", [0x8E], 0x83, 255, 0, 0, 0x8E, 2),
    ("ace_matches_rank", [0x0E], 0x8E, 255, 0, 0, 0x0E, 0),
    ("ace_changes_nomination", [0x0E], 0x8E, 1, 0, 0, 0x0E, 0),
    ("nomination_matches_suit", [0x43], 0x8E, 1, 0, 0, 0x43, 255),
    ("red_jack_residual_draws", [0xCB, 0x0B], 0x4B, 255, 5, 0, None, 255),
    ("black_jack_can_be_countered", [0x0B], 0xCB, 255, 5, 0, 0x0B, 255),
    ("two_counter_precedes_ace", [0x0E, 0x42], 0x82, 255, 2, 0, 0x42, 255),
    ("seven_counter_precedes_ace", [0x0E, 0x47], 0x87, 255, 0, 1, 0x47, 255),
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["make"], cwd=ROOT, check=True)
    source = """!source "src/main.asm"
!source "src/autoplay.asm"
* = $9000
fixture_start:
 jsr init_buffers
 lda #$60
 sta transport_send_frame
 lda #0
 sta zp_current_turn
 sta zp_my_index
"""
    for index, (_, hand, top, nomination, draws, skips, _, _) in enumerate(CASES):
        values = {
            "AUTOPLAY_WAITING": 0,
            "zp_hand_count": len(hand),
            "DISCARD_TOP": top,
            "NOMINATED_SUIT": nomination,
            "PENDING_DRAWS": draws,
            "PENDING_SKIPS": skips,
        }
        values.update({f"MY_HAND+{i}": card for i, card in enumerate(hand)})
        for address, value in values.items():
            source += f" lda #{value}\n sta {address}\n"
        source += f""" jsr autoplay_turn
 ldx #63
copy_{index}:
 lda SERIAL_TX_BUF,x
 sta ${0xC800 + index * 64:04x},x
 dex
 bpl copy_{index}
"""
    source += " lda #$aa\n sta $cbff\nhalt: jmp halt\n"
    asm = OUT / "fixture.asm"
    asm.write_text(source)
    prg, symbols = OUT / "fixture.prg", OUT / "fixture.sym"
    subprocess.run(
        [
            os.environ.get("ASM198X", "asm198x"),
            "--dialect",
            "acme",
            "--prg",
            "-I",
            ".",
            str(asm),
            f"--sym={symbols}",
            "-o",
            str(prg),
        ],
        cwd=ROOT,
        check=True,
    )
    match = re.search(
        r"^fixture_start\s*=\s*\$([0-9a-fA-F]+)", symbols.read_text(), re.MULTILINE
    )
    assert match is not None, "Missing assembled entry point"
    entry = int(match[1], 16)
    binary = bytearray(prg.read_bytes())
    binary[2:15] = (
        bytes([0x0D, 8, 10, 0, 0x9E]) + str(entry).encode() + bytes([0, 0, 0])
    )
    prg.write_bytes(binary)
    steps = [
        {"action": "run_frames", "frames": 200},
        {
            "action": "type_string",
            "text": "RUN\n",
            "hold_frames": 2,
            "settle_frames": 60,
        },
        {"action": "memory_read", "addr": 0xCBFF, "len": 1},
    ]
    steps.extend(
        {"action": "memory_read", "addr": 0xC800 + i * 64, "len": 64}
        for i in range(len(CASES))
    )
    session = OUT / "session.json"
    session.write_text(json.dumps(steps))
    emulator = Path(
        os.environ.get(
            "EMU198X_C64",
            str(
                Path.home() / "Projects/198x/Emu198x/emu198x/target/release/emu198x-c64"
            ),
        )
    )
    result = subprocess.run(
        [
            str(emulator),
            "--headless",
            "--rom-dir",
            str(Path.home() / ".emu198x/roms/commodore-c64"),
            "--load",
            str(prg),
            "--script",
            str(session),
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=120,
    )
    (OUT / "report.json").write_text(result.stdout)
    assert result.returncode == 0, result.stderr
    reads = [
        o["bytes"]
        for o in json.loads(result.stdout)["observations"]
        if o["kind"] == "memory_read"
    ]
    assert reads[0] == [0xAA], "Fixture did not finish"
    assert len(reads) == len(CASES) + 1 and all(
        len(frame) == 64 for frame in reads[1:]
    ), "Missing encoded frames"
    failures = []
    for index, (name, _, _, _, _, _, card, suit) in enumerate(CASES):
        frame = bytes(reads[index + 1])
        assert frame[:5] == b"RACH\x02", (name, "missing RUBP v2 frame")
        assert int.from_bytes(frame[14:16]) == binascii.crc_hqx(
            frame[:14] + b"\0\0" + frame[16:], 0xFFFF
        ), (name, "CRC")
        actual = (frame[5], frame[16], frame[17], frame[49])
        expected = (4, 1, card, suit) if card is not None else (5, 0, 1, 0)
        if actual != expected:
            failures.append(f"{name}: got {actual}, want {expected}")
        else:
            print(f"PASS {name}")
    assert not failures, "\n".join(failures)
    print(f"All {len(CASES)} actual assembly move/encoder cases passed")


if __name__ == "__main__":
    main()
