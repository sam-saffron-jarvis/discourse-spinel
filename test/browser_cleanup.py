#!/usr/bin/env python3
"""Regression: SIGTERM after real rendering must release owned native3498.

Runs before the complete browser proof, which replaces the interrupted run's
partial report/screenshots with complete desktop/phone evidence.
"""
import json
from pathlib import Path
import signal
import socket
import subprocess
import time


def assert_port_free():
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", 3498))


assert_port_free()
shot = Path("build/browser/prefix-desktop.png")
previous = shot.stat().st_mtime_ns if shot.exists() else None
Path("build").mkdir(exist_ok=True)
with Path("build/browser-cleanup.log").open("w") as log:
    child = subprocess.Popen(["python3", "test/browser_smoke.py", "--base-uri", "/node/jarvis/widgets/discourse-spinel-app"], stdout=log, stderr=log)
    try:
        deadline = time.monotonic() + 45
        rendered = False
        while time.monotonic() < deadline and child.poll() is None:
            rendered = shot.exists() and shot.stat().st_mtime_ns != previous
            if rendered:
                break
            time.sleep(.05)
        assert rendered and child.poll() is None, "must interrupt an active owned browser after desktop rendering; see build/browser-cleanup.log"
        start = time.monotonic()
        child.send_signal(signal.SIGTERM)
        code = child.wait(timeout=45)
        elapsed = time.monotonic() - start
        assert code == 143, (code, "see build/browser-cleanup.log")
    finally:
        if child.poll() is None:
            child.terminate()
            child.wait(timeout=45)
assert_port_free()
report = {"signal": "SIGTERM", "interrupted_after_desktop_screenshot": True,
          "exit_code": code, "shutdown_seconds": elapsed, "owned_native3498_released": True}
Path("build/browser-cleanup.json").write_text(json.dumps(report, indent=2) + "\n")
print("Browser signal cleanup passed: rendered desktop interrupted; owned native3498 released")
