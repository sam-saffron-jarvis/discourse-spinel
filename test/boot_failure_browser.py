#!/usr/bin/env python3
"""A missing core module must show a retryable boot error, never a white screen.
Owns only port3529 and its native child; uses task-owned PG5499/Valkey6399.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import time
from urllib.request import urlopen
from playwright.sync_api import sync_playwright

PORT = 3529
ORIGIN = f"http://127.0.0.1:{PORT}"
PREFIX = "/node/jarvis/widgets/discourse-spinel-app"
OUT = Path("build/boot-failure")
OUT.mkdir(parents=True, exist_ok=True)
with socket.socket() as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", PORT))
env = dict(os.environ)
env.update(PORT=str(PORT), MINIMAL_BASE_URI=PREFIX, MINIMAL_ORIGIN=ORIGIN,
           MINIMAL_PROFILER="1", DATABASE_URL="postgres://discourse@127.0.0.1:5499/discourse_development",
           REDIS_URL="redis://127.0.0.1:6399/0")
with (OUT / "server.log").open("w") as log:
    child = subprocess.Popen(["build/bin/discourse"], env=env, stdout=log, stderr=log)
    try:
        for _ in range(100):
            if child.poll() is not None:
                raise RuntimeError("owned native child exited before readiness")
            try:
                with urlopen(ORIGIN + PREFIX + "/srv/status", timeout=1) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(.1)
        else:
            raise TimeoutError("owned native child not ready")
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path="/usr/bin/chromium", headless=True,
                                                args=["--no-sandbox", "--disable-dev-shm-usage"])
            try:
                context = browser.new_context(service_workers="block")
                page = context.new_page()
                injected = []
                def route_request(route):
                    url = route.request.url
                    if not url.startswith(ORIGIN + "/"):
                        raise AssertionError("unexpected external request: " + url)
                    if "/assets/js/chunk-" in url and not injected:
                        injected.append(url)
                        route.fulfill(status=502, content_type="text/plain", body="controlled missing module")
                    else:
                        route.continue_()
                page.route("**/*", route_request)
                page.goto(ORIGIN + PREFIX + "/latest", wait_until="domcontentloaded")
                page.locator("#native-boot-error").wait_for(timeout=10000)
                assert injected, "negative control must actually withhold a core chunk"
                assert page.locator("html").get_attribute("data-native-boot") == "failed"
                assert page.locator("#native-boot-progress").count() == 0
                assert page.locator(".topic-list .topic-list-item").count() == 0
                page.screenshot(path=str(OUT / "visible-error.png"))
                page.get_by_role("button", name="Reload page", exact=True).click()
                page.locator(".topic-list .topic-list-item a.title").first.wait_for(timeout=20000)
                page.locator(".profiler-results .profiler-result").first.wait_for(timeout=10000)
                assert page.locator(".topic-list .topic-list-item").count() == 20
                assert page.locator("#native-boot-error").count() == 0
                assert page.locator("#native-boot-progress").count() == 0
                assert page.locator("html").get_attribute("data-native-boot") == "complete"
                report = {"injected_502": len(injected), "visible_boot_error": True,
                          "reload_button_recovered": True, "topics_after_reload": 20,
                          "profiler_after_reload": True, "scope": "owned native child; injected module502"}
                (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
                print(json.dumps(report))
                context.close()
            finally:
                browser.close()
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
