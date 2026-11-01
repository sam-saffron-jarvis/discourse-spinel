#!/usr/bin/env python3
"""Native server HTTP contract; no Rails HTTP server or DB mutations."""
import json
import pathlib
import socket
from html.parser import HTMLParser
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def request(path, code=200, method="GET", headers=None, content_type="application/json; charset=utf-8", raw=False):
    try:
        response = urlopen(Request("http://127.0.0.1:3498" + path, method=method, headers=headers or {}), timeout=5)
    except HTTPError as error:
        response = error
    with response:
        assert response.status == code, (path, response.status, code)
        assert response.headers["Content-Type"] == content_type
        assert response.headers["X-Content-Type-Options"] == "nosniff"
        body = response.read()
        assert int(response.headers["Content-Length"]) == len(body)
        assert response.headers["Cache-Control"] == "no-store"
    return body if raw else json.loads(body)


class Document(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.tags = []
        self.scripts = {}
        self.current = None
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append((tag, attrs))
        if tag == "script":
            self.current = attrs.get("id")
            if self.current:
                self.scripts[self.current] = ""

    def handle_endtag(self, tag):
        if tag == "script":
            self.current = None

    def handle_data(self, data):
        if self.current:
            self.scripts[self.current] += data


# An unused browser preconnect may close cleanly without an HTTP request.
with socket.create_connection(("127.0.0.1", 3498), timeout=5) as idle:
    idle.shutdown(socket.SHUT_WR)
    assert idle.recv(1024) == b"", "EOF is not a malformed HTTP route"
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
document = Document(request("/latest", content_type="text/html; charset=utf-8", raw=True).decode())
assert ("section", {"id": "main"}) in document.tags, "actual Ember mount point"
assert not any(tag == "table" for tag, _ in document.tags), "no bespoke server-rendered topic table"
setup = next(attrs for tag, attrs in document.tags if attrs.get("id") == "data-discourse-setup")
assert setup["data-base-uri"] == ""
preloads = {key: json.loads(value) for key, value in json.loads(document.scripts["data-preloaded"]).items()}
assert preloads["topic_list"] == latest, "HTML topics must be live native API data"
assert preloads["site"]["categories"] and preloads["siteSettings"]["title"]
assert {"site", "siteSettings", "themeSiteSettingOverrides", "customHTML", "banner", "customEmoji", "isReadOnly", "isStaffWritesOnly", "activatedThemes", "upcomingChanges", "topic_list"} <= preloads.keys()
modules = [attrs["src"] for tag, attrs in document.tags if tag == "script" and attrs.get("type") == "module" and attrs.get("src")]
assert modules, "real core module scripts must load; preload diagnostics alone are insufficient"
for url in modules:
    request(url, content_type="text/javascript; charset=utf-8", raw=True)
for path in ("/assets/../compile.json", "/assets/%2e%2e/compile.json", "/assets/discourse/manifest/manifest.json", "/assets/missing.js", "/assets/.hidden.js", "/data/emoji-unicode.json", "/assets/native/locale/en.js.map", "/assets/native/locale/en.js.gz"):
    request(path, 404)
request("/latest?order=views", 400)
request("/latest.json", 405, "POST")
request("/missing", 404)
# Previous bad inputs did not crash the process or poison its PG transaction.
assert request("/latest.json") == latest
print(f"HTTP contract passed: {len(ids)} live topics, rejected filters/methods, native Discourse HTML/modules and static boundaries")
