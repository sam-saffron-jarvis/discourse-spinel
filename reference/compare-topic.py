#!/usr/bin/env python3
"""Compare native anonymous topic JSON to a fresh read-only Rails projection.

File-only: no HTTP requests. Every key actually emitted by the native topic body is
compared against the corresponding source getter; unprojected candidate keys fail.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def differences(expected, actual, path="$", limit=100):
    if type(expected) is not type(actual):
        return [f"{path}: type {type(expected).__name__} != {type(actual).__name__}"]
    if isinstance(expected, dict):
        result = []
        for key in sorted(set(expected) | set(actual)):
            if key not in expected:
                result.append(f"{path}.{key}: native-only key (no source getter in projection)")
            elif key not in actual:
                result.append(f"{path}.{key}: missing native key")
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


def load_topics(path: Path):
    if path.is_dir():
        preferred = path / "topic-native.json"
        files = [preferred] if preferred.is_file() else sorted(path.glob("topic-*.json"))
        if not files:
            raise SystemExit(f"No topic-native.json or topic-*.json documents in {path}")
        documents = [json.loads(file.read_text()) for file in files]
    else:
        documents = [json.loads(path.read_text())]

    topics = {}
    for doc in documents:
        if isinstance(doc, dict) and isinstance(doc.get("topics"), list):
            rows = doc["topics"]
            for row in rows:
                if not isinstance(row, dict):
                    raise SystemExit("Expected each topics[] item to be a JSON object")
                topic = row.get("topic", row)
                topic_id = topic.get("id")
                if topic_id in topics:
                    raise SystemExit(f"Duplicate candidate topic ID {topic_id}")
                topics[topic_id] = row
        elif isinstance(doc, dict):
            topic_id = doc.get("id")
            if topic_id in topics:
                raise SystemExit(f"Duplicate candidate topic ID {topic_id}")
            topics[topic_id] = doc
        else:
            raise SystemExit("Expected a JSON topic object or {topics:[...]}")
    if None in topics:
        raise SystemExit("Candidate topic document has no top-level id")
    return topics


def project_candidate(row):
    native = row.get("topic", row)
    stream = native.get("post_stream", row.get("post_stream"))
    details = native.get("details", row.get("details"))
    if not isinstance(stream, dict) or not isinstance(stream.get("posts"), list):
        raise ValueError("candidate has no post_stream.posts array")
    if not isinstance(details, dict):
        raise ValueError("candidate has no details object")
    topic = {key: value for key, value in native.items() if key not in ("post_stream", "details")}
    return {"topic": topic, "details": details, "post_stream": stream}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", default="build/topic-rails.json", help="fresh capture-topic-rails.rb output")
    parser.add_argument("--candidate", required=True, help="native topic JSON file or directory")
    args = parser.parse_args()
    expected_doc = json.loads(Path(args.expected).read_text())
    if expected_doc.get("contract") != "minimal-topic-v1":
        raise SystemExit("Expected capture does not declare minimal-topic-v1")
    expected_rows = {row["request"]["topic_id"]: row for row in expected_doc.get("topics", [])}
    candidates = load_topics(Path(args.candidate))

    candidate_ids = set(candidates)
    expected_ids = set(expected_rows)
    if candidate_ids != expected_ids:
        missing = sorted(expected_ids - candidate_ids)
        extras = sorted(candidate_ids - expected_ids)
        raise SystemExit(f"Candidate topic IDs must exactly match capture; missing={missing}, extra={extras}")
    matched_ids = sorted(expected_ids)
    failures = []
    for topic_id in matched_ids:
        expected_row = expected_rows[topic_id]
        expected = {
            "topic": expected_row["topic"],
            "details": expected_row["details"],
            "post_stream": expected_row["post_stream"],
        }
        try:
            actual = project_candidate(candidates[topic_id])
            failures.extend(f"topic {topic_id}: {item}" for item in differences(expected, actual))
        except (KeyError, ValueError) as exc:
            failures.append(f"topic {topic_id}: malformed candidate: {exc}")
    if failures:
        print("Native topic projection comparison FAILED:", file=sys.stderr)
        print("\n".join(f"- {line}" for line in failures), file=sys.stderr)
        return 1
    print(f"Native topic projection matches minimal-topic-v1 for {len(matched_ids)} topics: {matched_ids}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
