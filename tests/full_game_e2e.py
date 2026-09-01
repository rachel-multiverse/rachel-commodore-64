#!/usr/bin/env python3
"""Complete a deterministic C64 game in Emu198x against the Go server.

Drives the real client PRG through the emulated user-port ESP-AT modem, so the
bytes crossing the link are the ones a Sven Petersen modem would carry: 8N1 at
9600 baud, bit-banged against CIA #2 PA2/PB0 (user-port pins M and C).
"""

from pathlib import Path
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SERVER = Path(os.environ.get("RACHEL_SERVER_DIR", ROOT.parent / "rachel-server"))
EMU = Path(os.environ.get("EMU198X_DIR", Path.home() / "Projects/198x/Emu198x/emu198x"))
EMU_BIN = EMU / "target/release/emu198x-c64"
ROMS = Path(os.environ.get("C64_ROM_DIR", Path.home() / ".emu198x/roms/commodore-c64"))
OUTPUT = ROOT / "build" / os.environ.get("RACHEL_E2E_OUTPUT", "e2e-output")
SEED = int(os.environ.get("RACHEL_E2E_SEED", "2"))
MIN_PLAYERS = int(os.environ.get("RACHEL_E2E_MIN_PLAYERS", "2"))
AI_PLAYERS = int(os.environ.get("RACHEL_E2E_AI_PLAYERS", "1"))
GAME_FRAMES = int(os.environ.get("RACHEL_E2E_GAME_FRAMES", "120000"))
WRITE_INTERVAL = os.environ.get("RACHEL_E2E_WRITE_INTERVAL", "0")
MODEL = os.environ.get("RACHEL_E2E_MODEL", "pal").lower()
# The client times its bits from a CIA timer rather than a counted loop, so it
# holds a real 2400 baud regardless of what the VIC-II is doing. No fudge
# factor: this is the rate a physical modem would be set to.
BAUD = int(os.environ.get("RACHEL_E2E_BAUD", "2400"))
PORT = int(os.environ.get("RACHEL_E2E_PORT", "6502"))


def require_environment() -> None:
    if not SERVER.is_dir():
        raise SystemExit(f"server checkout not found at {SERVER}; set RACHEL_SERVER_DIR")
    if not EMU_BIN.is_file():
        raise SystemExit(
            f"{EMU_BIN} not found; build it with "
            f"`cargo build --release -p emu198x-c64` in {EMU}"
        )
    if not ROMS.is_dir():
        raise SystemExit(f"C64 ROMs not found at {ROMS}; set C64_ROM_DIR")


def wait_for_server(process: "subprocess.Popen[str]", port: int) -> None:
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"server exited early with {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)
    raise SystemExit(f"server did not listen on {port} within 30s")


def stop_group(process: "subprocess.Popen[str]") -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)


def main() -> None:
    require_environment()
    subprocess.run(["make", "e2e-prg"], cwd=ROOT, check=True)
    prg = ROOT / "build/rachel-e2e.prg"

    shutil.rmtree(OUTPUT, ignore_errors=True)
    OUTPUT.mkdir(parents=True)
    session_path = OUTPUT / "session.json"
    screenshot_path = OUTPUT / "final.png"
    server_log_path = OUTPUT / "server.log"
    emulator_log_path = OUTPUT / "emulator.json"

    # The client is a BASIC-stub PRG, so it starts with RUN; then any key opens
    # the host prompt and the address dials out through the emulated modem.
    session_path.write_text(json.dumps([
        {"action": "run_frames", "frames": 200},
        {"action": "type_string", "text": "RUN\n", "hold_frames": 2, "settle_frames": 40},
        # Let the client draw its "press any key" prompt before pressing one:
        # a key delivered while BASIC is still starting it is simply lost.
        {"action": "run_frames", "frames": 120},
        {"action": "press_key", "key": "Space", "hold_frames": 3},
        {"action": "run_frames", "frames": 60},
        {"action": "type_string", "text": f"127.0.0.1:{PORT}\n", "hold_frames": 2,
         "settle_frames": 40},
        {"action": "run_frames", "frames": GAME_FRAMES},
    ], indent=2) + "\n")

    command = ["go", "run", ".", "serve", "--addr", f"127.0.0.1:{PORT}",
               "--min-players", str(MIN_PLAYERS), "--ai-players", str(AI_PLAYERS),
               "--auto-start", "1ms", "--ai-delay", "0",
               "--random-seed", str(SEED),
               "--vic20-write-interval", WRITE_INTERVAL]
    with server_log_path.open("w+") as server_log:
        server = subprocess.Popen(command, cwd=SERVER, stdout=server_log,
                                  stderr=subprocess.STDOUT, text=True,
                                  start_new_session=True)
        try:
            wait_for_server(server, PORT)
            result = subprocess.run([
                str(EMU_BIN), "--headless", "--model", MODEL,
                "--rom-dir", str(ROMS),
                "--load", str(prg), "--esp-at-tcp",
                "--esp-at-baud", str(BAUD),
                "--script", str(session_path),
                "--screenshot", str(screenshot_path),
                "--print-query", "userport.esp_at.error",
            ], cwd=EMU, text=True, capture_output=True, timeout=600)
            emulator_log_path.write_text(result.stdout + result.stderr)
        finally:
            stop_group(server)

    server_text = server_log_path.read_text()
    if result.returncode:
        raise SystemExit(f"emulator failed; see {emulator_log_path}")
    if "Game finished" not in server_text:
        raise SystemExit(f"game did not finish; see {server_log_path}")
    if "Client error" in server_text:
        raise SystemExit(f"server rejected a client action; see {server_log_path}")
    if not screenshot_path.is_file():
        raise SystemExit("emulator did not produce the final screenshot")
    if screenshot_path.stat().st_size < 1_000:
        raise SystemExit("final screenshot is unexpectedly blank or truncated")
    print(f"Complete deterministic C64 game passed: {OUTPUT}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.TimeoutExpired as error:
        print(f"timed out: {error}", file=sys.stderr)
        raise SystemExit(1)
