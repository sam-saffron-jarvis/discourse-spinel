#!/usr/bin/env python3
"""Exercise the real rack-mini-profiler UI on native /latest.

This script owns only the child it starts. It uses the task-owned PostgreSQL
DSN, localhost port3528 only, the actual locked upstream JS/CSS, and blocks
all browser requests outside the local listener. Evidence is sanitized: response
bodies are never saved. The native core redacts bind values, literal values, and
SQL comments before screenshots; safe SQL structure/placeholders remain visible.
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

HOST = "127.0.0.1"
PORT = 3528
TASK_DATABASE = "postgres://discourse@127.0.0.1:5499/discourse_development"
TASK_REDIS = "redis://127.0.0.1:6399/0"
DEFAULT_PREFIX = "/node/jarvis/widgets/discourse-spinel-app"
OUTPUT = Path("build/profiler-browser")
interrupted_signal = 0


def terminate(signum, _frame):
    # Do not raise inside Playwright's greenlet; unwind at explicit checkpoints.
    global interrupted_signal
    interrupted_signal = signum


def check_interrupted():
    if interrupted_signal:
        raise SystemExit(128 + interrupted_signal)


def assert_port_free():
    with socket.socket() as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((HOST, PORT))
        except OSError as error:
            raise RuntimeError(f"task-owned browser port {PORT} is occupied; refusing to attach or stop it") from error


def main():
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-uri", default=os.environ.get("MINIMAL_BASE_URI", DEFAULT_PREFIX))
    args = parser.parse_args()
    prefix = args.base_uri.rstrip("/")
    if prefix and (not prefix.startswith("/") or ".." in prefix.split("/")):
        parser.error("--base-uri must be a normalized local path prefix")
    if os.environ.get("DATABASE_URL", TASK_DATABASE) != TASK_DATABASE:
        parser.error(f"refusing non-task database; DATABASE_URL must be {TASK_DATABASE}")
    if os.environ.get("REDIS_URL", TASK_REDIS) != TASK_REDIS:
        parser.error(f"refusing non-task Valkey; REDIS_URL must be {TASK_REDIS}")
    assert_port_free()

    OUTPUT.mkdir(parents=True, exist_ok=True)
    origin = f"http://{HOST}:{PORT}"
    base = origin + prefix
    env = dict(os.environ)
    env.update(PORT=str(PORT), MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=origin,
               MINIMAL_PROFILER="1", DATABASE_URL=TASK_DATABASE, REDIS_URL=TASK_REDIS)
    child = None
    evidence = {"port": PORT, "prefix": prefix, "viewports": [], "blocked_remote": [], "requests": []}
    with (OUTPUT / "server.log").open("w") as log:
        child = subprocess.Popen(["build/bin/discourse"], env=env, stdout=log, stderr=log)
        try:
            for _ in range(150):
                check_interrupted()
                if child.poll() is not None:
                    raise RuntimeError(f"native child exited with {child.returncode}; see {OUTPUT / 'server.log'}")
                try:
                    with urlopen(base + "/srv/status", timeout=1) as response:
                        if response.status == 200:
                            break
                except OSError:
                    time.sleep(.1)
            else:
                raise TimeoutError(f"native child did not become ready on {PORT}; see {OUTPUT / 'server.log'}")

            check_interrupted()
            with urlopen(base + "/latest.json", timeout=10) as response:
                topics = json.load(response)["topic_list"]["topics"]
            assert topics, "live PG-backed latest must contain topics"
            emoji_map = json.loads(Path("data/emoji-unicode.json").read_text())
            reports = []
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(
                    executable_path="/usr/bin/chromium", headless=True,
                    args=["--no-sandbox", "--disable-dev-shm-usage"])
                try:
                    for name, width, height, mobile in (("desktop", 1440, 1000, False), ("phone", 390, 844, True)):
                        check_interrupted()
                        report = {"viewport": name, "page_errors": [], "console_errors": [],
                                  "failed_requests": [], "response_statuses": [], "profiler_requests": []}
                        reports.append(report)
                        context = browser.new_context(viewport={"width": width, "height": height},
                                                     is_mobile=mobile, has_touch=mobile, device_scale_factor=1)
                        page = context.new_page()
                        page.on("pageerror", lambda error, r=report: r["page_errors"].append(str(error)))
                        page.on("console", lambda msg, r=report: r["console_errors"].append(msg.text) if msg.type == "error" else None)
                        page.on("requestfailed", lambda req, r=report: r["failed_requests"].append({"url": req.url, "failure": req.failure}))
                        page.on("response", lambda response, r=report: r["response_statuses"].append({"url": response.url, "status": response.status}))

                        def local_only(route):
                            if route.request.url.startswith(origin + "/"):
                                route.continue_()
                            else:
                                evidence["blocked_remote"].append(route.request.url)
                                route.abort()
                        page.route("**/*", local_only)
                        page.on("request", lambda request, r=report: r["profiler_requests"].append(
                            {"method": request.method, "url": request.url.split("?", 1)[0],
                             "requested_with": request.headers.get("x-requested-with")})
                            if "/mini-profiler-resources/" in request.url else None)

                        navigation = page.goto(base + "/latest", wait_until="domcontentloaded", timeout=20000)
                        check_interrupted()
                        assert navigation is not None and navigation.status == 200, "native /latest failed"
                        bootstrap = page.locator("script#mini-profiler")
                        bootstrap.wait_for(state="attached", timeout=15000)
                        attrs = bootstrap.evaluate("el => ({src:el.src, css:new URL(el.dataset.cssUrl, location.href).href, path:el.dataset.path, id:el.dataset.currentId, ids:el.dataset.ids})")
                        expected_path = prefix + "/mini-profiler-resources/"
                        assert attrs["src"].startswith(origin + expected_path + "includes.js?"), attrs
                        assert attrs["css"].startswith(origin + expected_path + "includes.css?"), attrs
                        assert attrs["path"] == expected_path, attrs
                        assert attrs["id"] and attrs["id"] in attrs["ids"].split(","), attrs
                        response_ids = navigation.headers.get("x-miniprofiler-ids", "")
                        assert attrs["id"] in response_ids.split(","), {"bootstrap": attrs["id"], "header": response_ids}
                        result = page.locator(".profiler-result").filter(has=page.locator(".profiler-button")).first
                        result.wait_for(state="attached", timeout=20000)
                        page.wait_for_function("id => window.MiniProfiler && window.MiniProfiler.fetchedIds.includes(id)", arg=attrs["id"], timeout=20000)
                        check_interrupted()

                        # Profiling must not break actual Ember latest semantic rendering.
                        page.wait_for_function("n => document.querySelectorAll('.topic-list .topic-list-item').length === n",
                                               arg=len(topics), timeout=20000)
                        rows = page.locator('.topic-list .topic-list-item').evaluate_all("""(rows, emojiMap) => rows.map(row => {
                          const link = row.querySelector('a.title');
                          const clone = link.cloneNode(true);
                          clone.querySelectorAll('img.emoji').forEach(img => img.replaceWith(document.createTextNode(emojiMap[img.alt] || `:${img.alt}:`)));
                          return {id: Number(row.dataset.topicId), title: clone.textContent.trim(), href: link.getAttribute('href')};
                        })""", emoji_map)
                        expected_rows = [{"id": topic["id"], "title": html.unescape(topic.get("unicode_title", topic["title"])),
                                          "href": f"{prefix}/t/{topic['slug']}/{topic['id']}"} for topic in topics]
                        assert rows == expected_rows, {"profiler_enabled_latest_mismatch": [(a, e) for a, e in zip(rows, expected_rows) if a != e]}
                        report["latest_semantic_topic_count"] = len(rows)

                        # Ensure the result was loaded from the actual same-prefix upstream resource POST.
                        result_url = origin + expected_path + "results"
                        assert any(item["url"] == result_url and item["method"] == "POST"
                                   and item["requested_with"] == "XMLHttpRequest"
                                   for item in report["profiler_requests"]), report["profiler_requests"]
                        requested_assets = {item["url"] for item in report["profiler_requests"] if item["method"] == "GET"}
                        assert origin + expected_path + "includes.css" in requested_assets, requested_assets
                        assert origin + expected_path + "vendor.js" in requested_assets, requested_assets
                        result.locator(".profiler-button").click()
                        popup = result.locator(".profiler-popup")
                        popup.wait_for(state="visible", timeout=5000)
                        if mobile:
                            mobile_layout = popup.evaluate("""p => ({
                              position: getComputedStyle(p).position,
                              left: getComputedStyle(p).left,
                              right: getComputedStyle(p).right,
                              rect: p.getBoundingClientRect().toJSON()
                            })""")
                            assert mobile_layout["position"] == "fixed" and mobile_layout["left"] == "0px", mobile_layout
                            assert mobile_layout["rect"]["x"] >= 0 and mobile_layout["rect"]["right"] <= width, mobile_layout
                            report["mobile_popup_contained"] = True
                        duration_text = result.locator(".profiler-duration-milliseconds").inner_text()
                        assert any(ch.isdigit() for ch in duration_text), duration_text
                        sql_badge = result.locator(".profiler-sql-count")
                        sql_badge.wait_for(state="attached", timeout=5000)
                        sql_count = int("".join(ch for ch in sql_badge.inner_text() if ch.isdigit()))
                        assert sql_count > 0, f"/latest returned no instrumented SQL in UI: {sql_badge.inner_text()!r}"
                        sql_link = popup.locator(".profiler-queries-show").first
                        sql_link.wait_for(state="visible", timeout=5000)
                        # The timing row may be inside the popup's own scroll area.
                        # Scroll it into the actual viewport, then use Playwright's pointer.
                        sql_link.evaluate("""el => {
                          const popup = el.closest('.profiler-popup');
                          let linkRect = el.getBoundingClientRect();
                          const popupRect = popup.getBoundingClientRect();
                          if (linkRect.right > innerWidth) popup.scrollLeft += linkRect.right - popupRect.right + 8;
                          if (linkRect.left < 0) popup.scrollLeft -= popupRect.left - linkRect.left + 8;
                          el.scrollIntoView({block:'center', inline:'center'});
                        }""")
                        bounds = sql_link.bounding_box()
                        pointer_blocked = False
                        if not bounds or bounds["x"] < 0 or bounds["x"] + bounds["width"] > width:
                            diagnostic = sql_link.evaluate("""e => {
                              const p = e.closest('.profiler-popup');
                              return {viewport: [innerWidth, innerHeight],
                                popup: {rect: p.getBoundingClientRect().toJSON(), scrollLeft: p.scrollLeft,
                                  scrollWidth: p.scrollWidth, clientWidth: p.clientWidth,
                                  overflow: getComputedStyle(p).overflow},
                                link: e.getBoundingClientRect().toJSON(),
                                parent: e.parentElement.getBoundingClientRect().toJSON()};
                            }""")
                            report["sql_pointer_blocked"] = "upstream popup control remains outside viewport after scrolling"
                            report["sql_pointer_layout"] = diagnostic
                            report["sql_pointer_box"] = bounds
                            page.screenshot(path=str(OUTPUT / f"{name}-offscreen-popup.png"), full_page=True)
                            pointer_blocked = True
                            # Close the ordinary details popup with a real outside pointer click;
                            # no synthetic click is used to claim a SQL drill-down.
                            page.mouse.click(width - 5, height - 5)
                            page.wait_for_function("document.querySelector('.profiler-popup').style.display === 'none'", timeout=5000)
                        else:
                            assert 0 <= bounds["y"] < height and bounds["y"] + bounds["height"] <= height, bounds
                            page.mouse.click(bounds["x"] + bounds["width"] / 2, bounds["y"] + bounds["height"] / 2)
                            query_box = result.locator(".profiler-queries")
                            query_box.wait_for(state="visible", timeout=5000)
                            sql_rows = query_box.locator("tbody tr:has(.query pre.prettyprint code)").evaluate_all(
                                "rows => rows.map(row => ({timing: row.querySelector('td.profiler-info')?.innerText || '', "
                                "query: row.querySelector('.query pre.prettyprint code')?.innerText || ''}))")
                            assert sql_count == len(sql_rows), {"badge_sql_count": sql_count, "rendered_sql_rows": len(sql_rows)}
                            assert sql_rows and all(row["query"].strip() for row in sql_rows), "SQL drill-down did not render query text"
                            assert any("SELECT" in row["query"].upper() for row in sql_rows), "rendered SQL has no SELECT statement"
                            assert all(any(ch.isdigit() for ch in row["timing"]) for row in sql_rows), "SQL timing/elapsed values missing"
                            report.update({"drilldown_query_rows": len(sql_rows),
                                           "drilldown_has_select": True, "drilldown_has_timing": True})
                            page.screenshot(path=str(OUTPUT / f"{name}.png"), full_page=True)

                        report.update({"bootstrap": {"asset_prefix_ok": True, "has_current_id": True},
                                       "request_duration_text": duration_text,
                                       "sql_count": sql_count, "url": page.url})
                        if pointer_blocked:
                            report["drilldown_query_rows"] = None
                            report["drilldown_has_select"] = False
                            report["drilldown_has_timing"] = False
                        else:
                            # Close the upstream query lightbox with a real backdrop click,
                            # then dismiss the still-open detail popup through its actual badge.
                            page.mouse.click(width - 5, height - 5)
                            page.wait_for_function("!document.querySelector('.profiler-queries-bg')", timeout=5000)
                            result.locator(".profiler-button").click()
                            page.wait_for_function("document.querySelector('.profiler-popup').style.display === 'none'", timeout=5000)

                        # Exercise the upstream fetch hook: a subsequent native /latest.json
                        # response carries a new profiler ID which the real client must fetch/render.
                        before_results = page.locator(".profiler-result").count()
                        async_result = page.evaluate("""async url => {
                          const response = await fetch(url);
                          const ids = response.headers.get('X-MiniProfiler-Ids') || '';
                          return {status: response.status, ids: ids.split(',').filter(Boolean)};
                        }""", base + "/latest.json")
                        assert async_result["status"] == 200 and async_result["ids"], async_result
                        async_id = async_result["ids"][0]
                        assert async_id != attrs["id"], "async request reused the page profile ID"
                        page.wait_for_function("id => window.MiniProfiler.fetchedIds.includes(id)", arg=async_id, timeout=15000)
                        check_interrupted()
                        page.wait_for_function("n => document.querySelectorAll('.profiler-result').length > n",
                                               arg=before_results, timeout=15000)
                        async_profile = page.locator(".profiler-result").last
                        async_profile.locator(".profiler-button").click()
                        async_profile.locator(".profiler-popup").wait_for(state="visible", timeout=5000)
                        async_sql_badge = async_profile.locator(".profiler-sql-count")
                        async_sql_badge.wait_for(state="attached", timeout=5000)
                        async_sql_count = int("".join(ch for ch in async_sql_badge.inner_text() if ch.isdigit()))
                        assert async_sql_count > 0, "async profiler result has no SQL badge count"
                        report.update({"async_profile_header_id_received": True,
                                       "async_profile_rendered_automatically": True,
                                       "async_sql_count": async_sql_count})
                        check_interrupted()
                        context.close()
                finally:
                    browser.close()
            evidence["viewports"] = reports
            for report in reports:
                assert not report["page_errors"], report["page_errors"]
                assert not report["console_errors"], report["console_errors"]
                assert not report["failed_requests"], report["failed_requests"]
                bad = [response for response in report["response_statuses"] if response["status"] >= 400]
                assert not bad, bad
            assert not evidence["blocked_remote"], evidence["blocked_remote"]
            (OUTPUT / "report.json").write_text(json.dumps(evidence, indent=2) + "\n")
            blockers = [r for r in reports if r.get("sql_pointer_blocked")]
            if blockers:
                raise AssertionError({"real_pointer_sql_drilldown_incomplete": [r["viewport"] for r in blockers],
                                      "evidence": str(OUTPUT / "report.json")})
            print(f"Profiler browser verification passed: native {prefix + '/latest' if prefix else '/latest'}, desktop + phone, "
                  f"{sum(r['sql_count'] for r in reports)} request SQL counts plus asynchronous profiles")
        finally:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            # Prove this script's listener was released; never kill/reuse another process.
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                probe.bind((HOST, PORT))


if __name__ == "__main__":
    main()
