#!/usr/bin/env python3
"""Real Chromium/Ember evidence against our OWNED native child, never Rails HTTP.

No remote fetches, writes to PG, shared pid files or listener reuse. Every failed
network request, console error and uncaught page error remains in build/browser/.
"""
import argparse
import html
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.request import urlopen

from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument("--base-uri", default=os.environ.get("MINIMAL_BASE_URI", "/node/jarvis/widgets/discourse-spinel-app"))
parser.add_argument("--root", action="store_true", help="also exercise unmounted root")
args = parser.parse_args()


interrupted_signal = 0


def terminate(signum, _frame):
    # Do not throw inside Playwright's greenlet/event-loop calls: that can strand
    # pending close tasks. Exit at explicit safe checkpoints, through finally.
    global interrupted_signal
    interrupted_signal = signum


def check_interrupted():
    if interrupted_signal:
        raise SystemExit(128 + interrupted_signal)


signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)
output = Path("build/browser")
output.mkdir(parents=True, exist_ok=True)
reports = []
emoji_map = json.loads(Path("data/emoji-unicode.json").read_text())


def run(prefix):
    check_interrupted()
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", 3498))  # never accidentally test a shared listener
    env = dict(os.environ, PORT="3498", MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN="http://127.0.0.1:3498",
               DATABASE_URL=os.environ["DSPINEL_PG_URL"] + "/discourse_development",
               REDIS_URL="redis://127.0.0.1:6399/0")
    label = "prefix" if prefix else "root"
    with (output / f"{label}-server.log").open("w") as log:
        child = subprocess.Popen(["build/bin/discourse"], env=env, stdout=log, stderr=log)
        try:
            origin = "http://127.0.0.1:3498"
            base = origin + prefix
            for _ in range(100):
                check_interrupted()
                assert child.poll() is None, "native child exited"
                try:
                    with urlopen(base + "/srv/status", timeout=2) as response:
                        assert response.status == 200
                    break
                except OSError:
                    time.sleep(.1)
            with urlopen(base + "/latest.json", timeout=10) as response:
                api = json.load(response)
            (output / f"{label}-latest.json").write_text(json.dumps(api, indent=2) + "\n")
            with sync_playwright() as p:
                browser = p.chromium.launch(executable_path="/usr/bin/chromium", headless=True,
                                            args=["--no-sandbox", "--disable-dev-shm-usage"])
                try:
                    for name, width, height, mobile in [("desktop", 1440, 1000, False), ("phone", 390, 844, True)]:
                        check_interrupted()
                        context = browser.new_context(viewport={"width": width, "height": height},
                                                      is_mobile=mobile, device_scale_factor=1, has_touch=mobile)
                        page = context.new_page()
                        evidence = dict(prefix=prefix, viewport=name, pageerrors=[], console=[], failed=[], responses=[], requests=[], rows=[])
                        reports.append(evidence)
                        page.on("pageerror", lambda error: evidence["pageerrors"].append({"message": str(error), "stack": error.stack}))
                        page.on("console", lambda msg: evidence["console"].append({"type": msg.type, "text": msg.text}))
                        page.on("request", lambda req: evidence["requests"].append({"url": req.url, "method": req.method, "body": req.post_data}) if req.resource_type in ("xhr", "fetch") else None)
                        page.on("requestfailed", lambda req: evidence["failed"].append({"url": req.url, "failure": req.failure}))
                        page.on("response", lambda res: evidence["responses"].append({"url": res.url, "status": res.status, "type": res.request.resource_type}))
                        def local_only(route):
                            if route.request.url.startswith(origin + "/"):
                                route.continue_()
                            else:
                                evidence["failed"].append({"url": route.request.url, "failure": "remote request forbidden"})
                                route.abort()
                        page.route("**/*", local_only)
                        try:
                            page.goto(base + "/latest", wait_until="commit", timeout=10000)
                            deadline = time.monotonic() + 30
                            while page.locator(".topic-list .topic-list-item a.title").count() == 0:
                                check_interrupted()
                                assert time.monotonic() < deadline, "actual Ember topic-list did not render"
                                page.wait_for_timeout(100)
                            for _ in range(20):
                                check_interrupted()
                                page.wait_for_timeout(100)
                        except Exception as error:
                            evidence["navigation_error"] = str(error)
                        evidence["rows"] = page.locator(".topic-list .topic-list-item").evaluate_all("""(rows, emojiMap) => rows.map(r => {
                          const link = r.querySelector('a.title');
                          const clone = link?.cloneNode(true);
                          clone?.querySelectorAll('img.emoji').forEach(img => img.replaceWith(document.createTextNode(emojiMap[img.alt] || `:${img.alt}:`)));
                          return {id: r.dataset.topicId, title: clone?.textContent.trim(), raw_title: link?.textContent.trim(), href: link?.getAttribute('href'), emoji: Array.from(link?.querySelectorAll('img.emoji') || [], i => ({alt: i.alt, src: i.src}))};
                        })""", emoji_map)
                        evidence["title_emoji_images"] = page.locator('.topic-list a.title img.emoji').evaluate_all("images => images.map(i => ({src:i.src, alt:i.alt, complete:i.complete, width:i.naturalWidth}))")
                        evidence["icons"] = page.locator('svg.d-icon use').evaluate_all("""uses => uses.map(use => {
                          const href = use.getAttribute('href') || use.getAttribute('xlink:href');
                          const symbol = href?.startsWith('#') ? document.getElementById(href.slice(1)) : null;
                          return {href, resolves: symbol?.localName === 'symbol'};
                        })""")
                        evidence["styles"] = page.evaluate("({font: getComputedStyle(document.body).fontFamily, primary: getComputedStyle(document.documentElement).getPropertyValue('--primary').trim()})")
                        evidence["module_scripts"] = page.locator('script[type="module"][src]').evaluate_all("scripts => scripts.map(s => s.src)")
                        evidence["url"] = page.url
                        page.screenshot(path=str(output / f"{label}-{name}.png"), full_page=True)
                        (output / f"{label}-{name}.html").write_text(page.content())
                        context.close()
                finally:
                    browser.close()
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    check_interrupted()
    expected = {str(t["id"]): t for t in api["topic_list"]["topics"]}
    for report in [r for r in reports if r["prefix"] == prefix]:
        assert not report.get("navigation_error"), report
        assert report["rows"], "diagnostic preloads are not browser rendering"
        assert [r["id"] for r in report["rows"]] == list(expected), report["rows"]
        for row in report["rows"]:
            topic = expected[row["id"]]
            assert row["title"] == html.unescape(topic.get("unicode_title", topic["title"])), row
            assert row["href"] == f"{prefix}/t/{topic['slug']}/{topic['id']}", row
        assert all(image["complete"] and image["width"] > 0 for image in report["title_emoji_images"]), report["title_emoji_images"]
        assert report["icons"] and all(icon["resolves"] for icon in report["icons"]), report["icons"]
        assert report["styles"]["primary"] and "Times" not in report["styles"]["font"], report["styles"]
        assert report["module_scripts"] and all(s.startswith(base + "/") for s in report["module_scripts"])
        assert all(response["url"].startswith(base + "/") for response in report["responses"]), "browser resource escaped configured mount"
        assert not report["pageerrors"], report["pageerrors"]
        assert not report["failed"], report["failed"]
        bad = [r for r in report["responses"] if r["status"] >= 400]
        assert not bad, bad
        assert not [c for c in report["console"] if c["type"] == "error"], report["console"]
        print(f"Browser passed: {label} {report['viewport']}, {len(report['rows'])} actual Ember topics matching live native API")


try:
    run(args.base_uri)
    if args.root and args.base_uri:
        run("")
finally:
    (output / "report.json").write_text(json.dumps(reports, indent=2) + "\n")
