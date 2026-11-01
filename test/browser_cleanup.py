#!/usr/bin/env python3
"""Regression: SIGTERM after real rendering must release owned native test port.

Runs before the complete browser proof, which replaces the interrupted run's
partial report/screenshots with complete desktop/phone evidence.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time

PORT = int(os.environ.get("MINIMAL_TEST_PORT", "3529"))
assert PORT in (3528, 3529), "parallel lane test ports only"


def assert_port_free():
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", PORT))


parser = argparse.ArgumentParser()
parser.add_argument("--topic", action="store_true")
args = parser.parse_args()
assert_port_free()
shots = ("build/topic-browser-profiler/prefix-desktop-*-click.png" if os.environ.get("MINIMAL_PROFILER") == "1" else "build/topic-browser/prefix-desktop-*-click.png") if args.topic else "build/browser/prefix-desktop.png"
previous = {str(path): path.stat().st_mtime_ns for path in Path('.').glob(shots)}
label = ("topic-browser-profiler-cleanup" if os.environ.get("MINIMAL_PROFILER") == "1" else "topic-browser-cleanup") if args.topic else "browser-cleanup"
command = ["python3", "test/topic_browser_smoke.py"] if args.topic else ["python3", "test/browser_smoke.py", "--base-uri", "/node/jarvis/widgets/discourse-spinel-app"]
Path("build").mkdir(exist_ok=True)
with Path(f"build/{label}.log").open("w") as log:
    child = subprocess.Popen(command, stdout=log, stderr=log)
    try:
        deadline = time.monotonic() + 45
        rendered = False
        while time.monotonic() < deadline and child.poll() is None:
            rendered = any(path.stat().st_mtime_ns != previous.get(str(path)) for path in Path('.').glob(shots))
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
          "exit_code": code, "shutdown_seconds": elapsed, "owned_native_test_port_released": True}
Path(f"build/{label}.json").write_text(json.dumps(report, indent=2) + "\n")
print("Browser signal cleanup passed: rendered desktop interrupted; owned native test port released")
