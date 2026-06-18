#!/usr/bin/env python3
import sys
import os
import argparse
import subprocess
import threading
import re
import signal
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

# Define DBus Object
class STTObject(dbus.service.Object):
    def __init__(self, bus_name, object_path):
        super().__init__(bus_name, object_path)

    @dbus.service.signal('org.kde.assistant.stt', signature='s')
    def TranscribedText(self, text):
        pass

# Global state
process = None
loop = None
accumulated_text = ""
ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

def parse_line_and_emit(raw_line, stt_obj):
    global accumulated_text
    try:
        with open("/tmp/whisper_daemon.log", "a") as f:
            f.write(f"RAW: {repr(raw_line)}\n")
    except Exception:
        pass

    # Check if this is a partial/in-progress line (whisper-stream uses ANSI line-clear)
    is_partial = '\x1b[2K' in raw_line

    # Strip ANSI codes and whitespace
    line = ansi_escape.sub('', raw_line).strip()

    try:
        with open("/tmp/whisper_daemon.log", "a") as f:
            f.write(f"CLEANED: {repr(line)} (partial={is_partial})\n")
    except Exception:
        pass

    # Skip empty lines and whisper-stream markers
    if not line or line == '[Start speaking]':
        return

    # Update accumulated text
    accumulated_text = line

    # Only emit on final (non-partial) lines
    if not is_partial and accumulated_text:
        try:
            with open("/tmp/whisper_daemon.log", "a") as f:
                f.write(f"EMITTING: {repr(accumulated_text)}\n")
        except Exception:
            pass

        GLib.idle_add(stt_obj.TranscribedText, accumulated_text)

def run_whisper(args, stt_obj):
    global process, loop

    # Construct command using stdbuf to force line-buffering on stdout/stderr
    cmd = [
        "stdbuf", "-oL", "-eL",
        args.bin,
        "-m", args.model,
        "-l", args.language,
        "-t", str(args.threads)
    ]

    # Add streaming refinement parameters (tuned for whisper-stream)
    cmd.extend(["--step", "2000", "--length", "7000", "-vth", "0.60"])

    print(f"Starting whisper-stream: {' '.join(cmd)}", file=sys.stderr)

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            text=True,
            bufsize=1
        )
    except Exception as e:
        print(f"Failed to spawn whisper-stream process: {e}", file=sys.stderr)
        GLib.idle_add(loop.quit)
        return

    # Read stdout line by line
    for line in process.stdout:
        parse_line_and_emit(line, stt_obj)

    # Clean up on completion/exit
    process.wait()
    print(f"whisper-stream subprocess finished with exit code {process.returncode}", file=sys.stderr)
    GLib.idle_add(loop.quit)

def signal_handler(signum, frame):
    global process, loop
    print(f"Terminating daemon via signal {signum}...", file=sys.stderr)
    if process:
        process.terminate()
    if loop:
        loop.quit()

def main():
    global loop

    parser = argparse.ArgumentParser(description="KDE Assistant Whisper DBus Daemon")
    parser.add_argument("--bin", default="whisper-stream", help="Path to whisper-stream / stream executable")
    parser.add_argument("--model", required=True, help="Path to ggml model bin file")
    parser.add_argument("--language", default="en", help="Language code (e.g. en, ar)")
    parser.add_argument("--threads", type=int, default=4, help="Number of processor threads")

    args = parser.parse_args()

    # Register signal handlers for clean exit
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Initialize DBus Loop
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    try:
        session_bus = dbus.SessionBus()
        bus_name = dbus.service.BusName('org.kde.assistant.stt', session_bus)
        stt_obj = STTObject(bus_name, '/org/kde/assistant/stt')
    except Exception as e:
        print(f"Failed to connect to DBus: {e}", file=sys.stderr)
        sys.exit(1)

    loop = GLib.MainLoop()

    # Start the whisper reader in a background thread
    reader_thread = threading.Thread(target=run_whisper, args=(args, stt_obj), daemon=True)
    reader_thread.start()

    # Run the main DBus event loop
    loop.run()

    print("Daemon stopped.", file=sys.stderr)

if __name__ == "__main__":
    main()
