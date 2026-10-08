"""Execute refreshed lobby seats through the production C64 waiting loop."""

from __future__ import annotations

import binascii
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/lobby-regression"


def frame(version: int, kind: int, payload: bytes) -> bytes:
    wire = bytearray(64)
    wire[:6] = b"RACH" + bytes([version, kind])
    wire[10:12] = b"\x00\x01"
    wire[16 : 16 + len(payload)] = payload
    checksum = binascii.crc_hqx(wire, 0xFFFF) if version == 2 else sum(wire)
    wire[14:16] = checksum.to_bytes(2, "big")
    return bytes(wire)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["make"], cwd=ROOT, check=True)
    cases = [(version, kind) for version in (1, 2) for kind in (3, 7)]
    source = """!source "src/main.asm"
* = $9000
fixture_start:
 jsr init_buffers
 lda #$60
 sta transport_send_frame
 lda #$4c
 sta transport_available
 lda #<fixture_available
 sta transport_available+1
 lda #>fixture_available
 sta transport_available+2
 lda #$4c
 sta rubp_receive
 lda #<fixture_receive
 sta rubp_receive+1
 lda #>fixture_receive
 sta rubp_receive+2
"""
    frames = []
    for index, (version, kind) in enumerate(cases):
        # The preceding player leaves: our seat moves from 1 to 0.
        welcome = frame(version, 2, bytes([0, 0, 0, 1, 2, 0, 0, 1, 1]))
        payload = bytearray(48)
        if kind == 3:
            payload[:5] = bytes([2, 0, 2, 3, 4])
            payload[35:37] = bytes([5, 40])
        else:
            payload[:5] = bytes([0, 1, 40, 5, 255])
        # A damaged preceding refresh must not update our identity.
        damaged = bytearray(frame(version, 2, bytes([0, 7, 0, 1, 2, 0, 0, 1, 1])))
        damaged[16] ^= 1
        frames.extend([bytes(damaged), welcome, frame(version, kind, bytes(payload))])
        source += f""" lda #<frames_{index}
 sta fixture_pointer
 lda #>frames_{index}
 sta fixture_pointer+1
 lda #1
 sta zp_player_id
 sta zp_my_index
 sta zp_game_id
 lda #0
 sta zp_player_id+1
 sta zp_game_id+1
 sta transport_link_down
 jsr wait_for_game
 lda zp_player_id
 sta ${0xC800 + index * 4:04x}
 lda zp_my_index
 sta ${0xC801 + index * 4:04x}
 lda zp_conn_state
 sta ${0xC802 + index * 4:04x}
 lda zp_game_id
 sta ${0xC803 + index * 4:04x}
 lda #0
 jsr rubp_send_draw_card
 ldx #63
copy_action_{index}:
 lda SERIAL_TX_BUF,x
 sta ${0xC900 + index * 64:04x},x
 dex
 bpl copy_action_{index}
"""
    source += """ lda #$aa
 sta $c8ff
halt: jmp halt
fixture_available:
 lda #0
 rts
fixture_receive:
 lda fixture_pointer
 sta zp_ptr2
 lda fixture_pointer+1
 sta zp_ptr2+1
 ldy #0
copy_frame:
 lda (zp_ptr2),y
 sta SERIAL_RX_BUF,y
 iny
 cpy #64
 bne copy_frame
 clc
 lda fixture_pointer
 adc #64
 sta fixture_pointer
 bcc received
 inc fixture_pointer+1
received:
 lda #0
 rts
fixture_pointer: !word 0
"""
    for index in range(len(cases)):
        source += f"frames_{index}:\n"
        for wire in frames[index * 3 : index * 3 + 3]:
            source += " !byte " + ",".join(map(str, wire)) + "\n"
    asm, symbols, prg = (
        OUT / name for name in ("fixture.asm", "fixture.sym", "fixture.prg")
    )
    asm.write_text(source)
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
    binary = bytearray(prg.read_bytes())
    binary[2:15] = (
        bytes([0x0D, 8, 10, 0, 0x9E]) + str(int(match[1], 16)).encode() + bytes(3)
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
        {"action": "memory_read", "addr": 0xC8FF, "len": 1},
        {"action": "memory_read", "addr": 0xC800, "len": len(cases) * 4},
        {"action": "memory_read", "addr": 0xC900, "len": len(cases) * 64},
    ]
    script = OUT / "session.json"
    script.write_text(json.dumps(steps))
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
            str(script),
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    (OUT / "report.json").write_text(result.stdout)
    assert result.returncode == 0, result.stderr
    reads = [
        row["bytes"]
        for row in json.loads(result.stdout)["observations"]
        if row["kind"] == "memory_read"
    ]
    assert len(reads) == 3 and reads[0] == [0xAA], "Lobby fixture did not complete"
    failures = []
    for index, case in enumerate(cases):
        identity = reads[1][index * 4 : index * 4 + 4]
        action = bytes(reads[2][index * 64 : index * 64 + 64])
        if identity != [0, 0, 4, 1] or action[8:12] != bytes([0, 0, 0, 1]):
            failures.append(
                f"v{case[0]} start=0x{case[1]:02x}: identity={identity}, action={action[8:12].hex()}"
            )
        assert action[:6] == b"RACH\x02\x05", "Next action was not encoded"
        assert int.from_bytes(action[14:16], "big") == binascii.crc_hqx(
            action[:14] + bytes(2) + action[16:], 0xFFFF
        )
    assert not failures, "Refreshed seat ignored: " + "; ".join(failures)
    print(
        "Four executed lobby cases pass: v1/v2, GAME_START/GAME_STATE, local seats and next action header"
    )


if __name__ == "__main__":
    main()
