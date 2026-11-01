#!/usr/bin/env python3
"""Compare anonymous candidate /latest against a read-only Rails capture.

The Rails snapshot is verification-only and never served. This probe sends GETs
only to loopback candidate origins and requires explicit task DB/Valkey URLs.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

TASK_DATABASE_URL = "postgres://discourse@127.0.0.1:5499/discourse_development"
TASK_REDIS_URL = "redis://127.0.0.1:6399/0"


def check_environment():
    if os.environ.get("DATABASE_URL") != TASK_DATABASE_URL:
        raise SystemExit(f"DATABASE_URL must be explicitly set to task DB: {TASK_DATABASE_URL}")
    if os.environ.get("REDIS_URL") != TASK_REDIS_URL:
        raise SystemExit(f"REDIS_URL must be explicitly set to task Valkey: {TASK_REDIS_URL}")


def local_url(value):
    parsed = urlsplit(value)
    if parsed.scheme not in ("http", "https") or parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise SystemExit(f"Refusing non-loopback URL: {value}")
    return value.rstrip("/")


def fetch(url, accept):
    request = Request(url, headers={"Accept": accept, "User-Agent": "ticket004-latest-reference/1"})
    try:
        with urlopen(request, timeout=30) as response:
            body, content_type, status = response.read(), response.headers.get("Content-Type", ""), response.status
    except (HTTPError, URLError) as exc:
        raise SystemExit(f"GET {url} failed: {exc}") from exc
    if status != 200:
        raise SystemExit(f"GET {url}: expected 200, got {status}")
    return body, content_type


def candidate_json(base, path):
    body, content_type = fetch(base + path, "application/json")
    if "json" not in content_type.lower():
        raise SystemExit(f"Expected JSON Content-Type from {base}{path}, got {content_type!r}")
    try:
        value = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Invalid JSON from {base}{path}: {exc}") from exc
    if not isinstance(value, dict) or not isinstance(value.get("topic_list"), dict) or not isinstance(value["topic_list"].get("topics"), list):
        raise SystemExit(f"Expected topic_list.topics array from {base}{path}")
    return value


def differences(expected, actual, path="$", limit=20):
    if type(expected) is not type(actual):
        return [f"{path}: type {type(expected).__name__} != {type(actual).__name__}"]
    if isinstance(expected, dict):
        result = []
        for key in sorted(set(expected) | set(actual)):
            if key not in expected:
                result.append(f"{path}.{key}: candidate-only key")
            elif key not in actual:
                result.append(f"{path}.{key}: Rails-only key")
            else:
                result.extend(differences(expected[key], actual[key], f"{path}.{key}", limit))
            if len(result) >= limit:
                break
        return result
    if isinstance(expected, list):
        if len(expected) != len(actual):
            return [f"{path}: length {len(expected)} != {len(actual)}"]
        result = []
        for index, (left, right) in enumerate(zip(expected, actual)):
            result.extend(differences(left, right, f"{path}[{index}]", limit))
            if len(result) >= limit:
                break
        return result
    return [] if expected == actual else [f"{path}: {expected!r} != {actual!r}"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare-recorded", "--recorded", dest="recorded", required=True, help="read-only capture-latest-rails.rb output; verification only")
    parser.add_argument("--candidate", default="http://127.0.0.1:3499", help="loopback candidate origin")
    args = parser.parse_args()
    check_environment()
    candidate = local_url(args.candidate)
    capture = json.loads(Path(args.recorded).read_text())
    responses = capture.get("responses", {})
    checks = []
    for key, path in (("latest", "/latest.json"), ("latest_page_1", "/latest.json?page=1")):
        if key not in responses:
            raise SystemExit(f"Recorded capture is missing {key}")
        checks.append((path, responses[key]["body"], candidate_json(candidate, path)))

    failed = []
    for label, expected, actual in checks:
        failed.extend(f"{label}: {item}" for item in differences(expected, actual))
    if failed:
        print("Recorded Rails /latest comparison FAILED:", file=sys.stderr)
        print("\n".join(f"- {item}" for item in failed), file=sys.stderr)
        return 1
    ids = [topic["id"] for topic in responses["latest"]["body"]["topic_list"]["topics"]]
    print(f"Recorded Rails latest JSON (both pages) matches exactly; topic IDs: {ids}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
