#!/usr/bin/env python3
"""Native server HTTP contract; no Rails HTTP server or DB mutations."""
import json
import pathlib
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def request(path, code=200, method="GET", headers=None):
    try:
        response = urlopen(Request("http://127.0.0.1:3498" + path, method=method, headers=headers or {}), timeout=5)
    except HTTPError as error:
        response = error
    with response:
        assert response.status == code, (path, response.status, code)
        assert response.headers["Content-Type"] == "application/json; charset=utf-8"
        body = response.read()
        assert int(response.headers["Content-Length"]) == len(body)
        assert response.headers["Cache-Control"] == "no-store"
    return json.loads(body)


status = request("/srv/status")
assert status["status"] == "ok" and status["database"] == "read-only"
latest = request("/latest.json")
page_1 = request("/latest.json?page=1")
assert request("/latest", headers={"Accept": "application/json"}) == latest
assert request("/latest?no_definitions=true&page=1", headers={"X-Requested-With": "XMLHttpRequest"}) == page_1
assert request("/latest.json?page=1&no_definitions=true") == page_1
assert latest["topic_list"]["topics"], "health-only smoke is forbidden"
assert latest["topic_list"]["filter"] == "latest"
ids = [t["id"] for t in latest["topic_list"]["topics"]]
assert len(ids) == len(set(ids)), "duplicate topics"
assert all(t["visible"] and t["archetype"] != "private_message" for t in latest["topic_list"]["topics"])
for name, body in (("latest-native", latest), ("latest-native-page-1", page_1)):
    pathlib.Path(f"build/{name}.json").write_text(json.dumps(body, indent=2) + "\n")
for query in ("page=-1", "page=2001", "page=garbage", "order=views", "page=1&search=private", "page=0%20OR%201=1", "page=" + "9" * 1000):
    request("/latest.json?" + query, 400)
request("/latest", 501)
request("/latest.json", 405, "POST")
request("/missing", 404)
# Previous bad inputs did not crash the process or poison its PG transaction.
assert request("/latest.json") == latest
print(f"HTTP contract passed: {len(ids)} live topics, rejected filters/methods, explicit frontend gap")
