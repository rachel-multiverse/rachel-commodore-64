#!/usr/bin/env python3
"""Check that a host which hangs up is noticed rather than waited on forever.

The Ultimate's network target announces a closed connection exactly once, as
"01,CONNECTION CLOSED BY HOST", and every poll after that reports no data. A
client that only accepts "00,OK" cannot tell the two apart, and one that blocks
until a frame arrives never comes back at all.

Both are checked here against a server that accepts the connection and closes
it without saying anything:

  zp_transport         must say Ultimate, so a silent fall back to the modem
                       cannot pass this off as a success;
  zp_conn_state        must have reached the handshake, which is what proves
                       the WELCOME wait was entered and cw_frames_left loaded;
  transport_link_down  must be set, so the close was recognised as a close;
  cw_frames_left       must have run down, which only happens if the blocking
                       receive returned - it stays loaded at 24 if the client
                       is parked inside it.
"""

from pathlib import Path
import json
import os
import re
import socket
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
EMU = Path(os.environ.get("EMU198X_DIR", Path.home() / "Projects/198x/Emu198x/emu198x"))
EMU_BIN = EMU / "target/release/emu198x-c64"
ROMS = Path(os.environ.get("C64_ROM_DIR", Path.home() / ".emu198x/roms/commodore-c64"))
PRG = ROOT / "build/rachel-linkloss.prg"
SYM = ROOT / "build/linkloss.sym"
FRAMES = int(os.environ.get("RACHEL_LINK_FRAMES", "1200"))

# Zero page, from src/zeropage.asm. Not in the symbol table: equates are not
# labels.
ZP_TRANSPORT = 0x0E
ZP_CONN_STATE = 0x30
TRANSPORT_ULTIMATE = 1
CONN_HANDSHAKE = 2


def symbol(table: str, name: str) -> int:
    match = re.search(rf"^{name}\s*=\s*\$([0-9A-Fa-f]+)", table, re.MULTILINE)
    if not match:
        raise SystemExit(f"{name} missing from {SYM}")
    return int(match.group(1), 16)


def serve_then_hang_up(listener: socket.socket, stop: threading.Event) -> None:
    """Accept whatever connects and drop it straight away."""
    listener.settimeout(0.5)
    while not stop.is_set():
        try:
            connection, _ = listener.accept()
        except (socket.timeout, OSError):
            continue
        connection.close()


def main() -> None:
    if not EMU_BIN.is_file():
        raise SystemExit(
            f"{EMU_BIN} not found; build it with "
            f"`cargo build --release -p emu198x-c64` in {EMU}"
        )
    if not PRG.is_file():
        raise SystemExit(f"{PRG} not found; run `make link-loss`")

    table = SYM.read_text()
    watched = {name: symbol(table, name)
               for name in ("transport_link_down", "cw_frames_left")}
    watched["zp_transport"] = ZP_TRANSPORT
    watched["zp_conn_state"] = ZP_CONN_STATE

    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(4)
    port = listener.getsockname()[1]

    session = ROOT / "build/link-loss.json"
    # The client is a BASIC-stub PRG, so it starts with RUN. Then the menu
    # wants a mode - O for online, since S would play a solo game that never
    # touches the network - and the prompt after it wants any key before the
    # address. Skipping that key costs the first character of the address.
    session.write_text(json.dumps([
        {"action": "run_frames", "frames": 200},
        {"action": "type_string", "text": "RUN\n", "hold_frames": 2,
         "settle_frames": 40},
        {"action": "run_frames", "frames": 120},
        {"action": "press_key", "key": "O", "hold_frames": 3},
        {"action": "run_frames", "frames": 60},
        {"action": "press_key", "key": "Space", "hold_frames": 3},
        {"action": "run_frames", "frames": 60},
        {"action": "type_string", "text": f"127.0.0.1:{port}\n",
         "hold_frames": 2, "settle_frames": 40},
        {"action": "run_frames", "frames": FRAMES},
        *({"action": "memory_read", "addr": addr, "len": 1}
          for addr in watched.values()),
    ], indent=2) + "\n")

    stop = threading.Event()
    server = threading.Thread(target=serve_then_hang_up, args=(listener, stop))
    server.start()
    try:
        result = subprocess.run([
            str(EMU_BIN), "--headless", "--rom-dir", str(ROMS),
            "--load", str(PRG), "--ultimate-net", "--script", str(session),
        ], cwd=EMU, text=True, capture_output=True, timeout=600)
    finally:
        stop.set()
        server.join()
        listener.close()

    if result.returncode:
        raise SystemExit(f"emulator failed:\n{result.stdout}\n{result.stderr}")

    report = json.loads(result.stdout)
    reads = [item["bytes"][0] for item in report["observations"]
             if item["kind"] == "memory_read"]
    values = dict(zip(watched, reads))

    if values["zp_transport"] != TRANSPORT_ULTIMATE:
        raise SystemExit(
            f"the client did not take the Ultimate transport: {values}"
        )
    if values["zp_conn_state"] != CONN_HANDSHAKE:
        raise SystemExit(
            f"the client never reached the WELCOME wait: {values}"
        )
    if not values["transport_link_down"]:
        raise SystemExit(
            f"the host hung up but the client did not notice: {values}"
        )
    if values["cw_frames_left"]:
        raise SystemExit(
            f"the client is still parked in a blocking receive: {values}"
        )

    print("Link-loss check passed: a host hanging up is recognised as a close "
          "and does not block the client")


if __name__ == "__main__":
    main()
