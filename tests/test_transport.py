#!/usr/bin/env python3
"""Source-contract checks for the two supported physical C64 transports."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    ultimate = (ROOT / "src/ultimate.asm").read_text()
    transport = (ROOT / "src/transport.asm").read_text()
    serial = (ROOT / "src/serial.asm").read_text()

    expected_uci = {
        "UCI_CONTROL     = $df1c",
        "UCI_COMMAND     = $df1d",
        "UCI_RESPONSE    = $df1e",
        "UCI_STATUS_DATA = $df1f",
        "UCI_ID          = $c9",
        "UCI_TARGET_NET  = $03",
        "UCI_OPEN_TCP    = $07",
        "UCI_CLOSE       = $09",
        "UCI_READ        = $10",
        "UCI_WRITE       = $11",
    }
    lines = ultimate.splitlines()
    missing = sorted(
        expected for expected in expected_uci
        if not any(line.startswith(expected) for line in lines)
    )
    assert not missing, f"missing official UCI constants: {missing}"

    assert "jsr ultimate_detect" in transport
    assert "jmp ultimate_connect" in transport
    assert "jmp modem_dial" in transport
    assert "RXD_BIT         = %00000001" in serial

    # The byte must be saved before TXA/TYA overwrite the accumulator.
    start = serial.index("serial_send_byte:")
    save = serial.index("sta zp_temp1", start)
    clobber = serial.index("txa", start)
    assert save < clobber

    print("Ultimate UCI and Sven Petersen Rev. 2 transport checks passed")


if __name__ == "__main__":
    main()
