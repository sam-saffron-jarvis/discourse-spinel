#!/usr/bin/env python3
"""Verify pinned original /latest inputs and inventory bounded compiler probes.

The survey emits nil placeholders at unsupported sites. Its output is
DIAGNOSTIC ONLY and is NEVER executed or accepted as application code.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
CHAIN = [
    "lib/topic_query.rb", "app/models/topic_list.rb", "lib/topic_list_responder.rb",
    "lib/topic_query_params.rb", "app/controllers/list_controller.rb",
    "app/controllers/application_controller.rb", "app/serializers/topic_list_serializer.rb",
    "app/serializers/topic_list_item_serializer.rb", "lib/application_layout_preloader.rb",
]
DIAGNOSTIC_RE = re.compile(
    r"^roundhouse: (?:(?P<path>.+?):(?P<line>\d+):(?P<column>\d+): )?"
    r"(?P<severity>warning|error|note)\[(?P<code>[^]]+)\]: (?P<message>.*)$"
)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def locate_strict_construct(data: bytes, diagnostic: str) -> dict | None:
    """Infer a source span only when stderr names a unique construct in the file."""
    tokens = re.findall(r"`([^`]+)`", diagnostic)
    method = next((token for token in tokens if re.fullmatch(r"[a-zA-Z_][a-zA-Z_0-9!?=]*", token)), None)
    option = next((token for token in tokens if token.endswith(":")), None)
    if not method or not option:
        return None
    candidates = []
    for match in re.finditer(rb"\b" + re.escape(method.encode()) + rb"\b", data):
        next_method = re.search(rb"\b" + re.escape(method.encode()) + rb"\b", data[match.end():])
        end = match.end() + next_method.start() if next_method else min(len(data), match.end() + 2048)
        if re.search(rb"\b" + re.escape(option[:-1].encode()) + rb"\s*:", data[match.end():end]):
            line = data[:match.start()].count(b"\n") + 1
            column = match.start() - (data.rfind(b"\n", 0, match.start()) + 1) + 1
            candidates.append({"start_byte": match.start(), "end_byte": match.end(),
                               "start_line": line, "start_column": column})
    return candidates[0] if len(candidates) == 1 else None


def parse_strict_failure(text: str, source_root: Path) -> dict | None:
    """Return actual strict-ingest refusal, not the preceding survey hint."""
    lines = [line for line in text.splitlines() if line.strip()]
    failure = next((line for line in lines if "unsupported construct in " in line), None)
    if failure is None:
        failure = next((line for line in lines if "] error:" in line or "error[" in line), None)
    if failure is None:
        return None
    result = {"text": failure, "source": None, "source_span": None,
              "classification": "strict_ingest_first_failure",
              "evidence_class": "source_ingest_fence_not_runtime_observation"}
    path_match = re.search(r"unsupported construct in (.+?\.rb):", failure)
    if path_match:
        absolute = Path(path_match.group(1)).resolve()
        try:
            rel = absolute.relative_to(source_root.resolve()).as_posix()
        except ValueError:
            rel = None
        if rel in CHAIN:
            result["source"] = rel
            raw = (source_root / rel).read_bytes()
            inferred_span = locate_strict_construct(raw, failure)
            if inferred_span:
                result["source_span"] = inferred_span
                result["source_location_status"] = "inferred from diagnostic construct tokens and unique original-source occurrence; compiler omitted line/column"
            else:
                result["source_location_status"] = "ingest refusal did not report line/column; construct match ambiguous or unavailable"
    return result

def source_span(data: bytes, line: int, column: int) -> dict | None:
    """Resolve one-based diagnostic positions to exact byte ranges."""
    lines = data.splitlines(keepends=True)
    if line < 1 or line > len(lines) or column < 1:
        return None
    start = sum(map(len, lines[:line - 1])) + column - 1
    line_content = lines[line - 1].rstrip(b"\r\n")
    if column - 1 > len(line_content):
        return None
    return {"start_byte": start, "end_byte": min(start + 1, sum(map(len, lines[:line - 1])) + len(line_content)),
            "start_line": line, "start_column": column}

def parse_diagnostics(text: str, source_root: Path) -> dict:
    """Parse observed diagnostics; unmatched text remains visible as malformed."""
    by_absolute = {}
    for rel in CHAIN:
        p = (source_root / rel).resolve()
        if p.exists():
            by_absolute[str(p)] = (rel, p.read_bytes())
    parsed, malformed = [], []
    for number, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        match = DIAGNOSTIC_RE.match(raw)
        if not match:
            malformed.append({"diagnostic_line": number, "text": raw})
            continue
        item = match.groupdict()
        item["diagnostic_line"] = number
        item["evidence_class"] = "source_or_lowering_diagnostic_not_runtime_observation"
        item["source_span"] = None
        item["source"] = None
        if item["path"]:
            found = by_absolute.get(str(Path(item["path"]).resolve()))
            if found:
                rel, data = found
                item["source"] = rel
                item["source_span"] = source_span(data, int(item["line"]), int(item["column"]))
                if item["source_span"] is None:
                    malformed.append({"diagnostic_line": number, "text": raw,
                                      "reason": "diagnostic position outside copied source"})
        parsed.append(item)
    counts = {}
    for d in parsed:
        key = f"{d['severity']}[{d['code']}]"
        counts[key] = counts.get(key, 0) + 1
    located = [d for d in parsed if d["source"] is not None and d["source_span"] is not None]
    return {"diagnostics": parsed, "diagnostic_categories": counts,
            "first_source_failure": located[0] if located else None,
            "malformed_lines": malformed}

def _run_probe(binary: Path, source_root: Path, output: Path, name: str, extra: list[str]) -> dict:
    emitted = output / f"{name}-emitted"
    argv = [str(binary), "--target", "spinel", *extra, str(source_root), "-o", str(emitted)]
    result = subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (output / f"{name}.stdout").write_text(result.stdout)
    (output / f"{name}.stderr").write_text(result.stderr)
    return {"argv": argv, "returncode": result.returncode,
            "stdout": f"{name}.stdout", "stderr": f"{name}.stderr",
            "emitted_directory": str(emitted), "diagnostics": parse_diagnostics(result.stderr, source_root)}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fidelity", type=Path, required=True, help="isolated fidelity worktree")
    ap.add_argument("--original-repo", type=Path, required=True, help="pinned original Discourse checkout")
    ap.add_argument("--roundhouse", type=Path, required=True, help="Roundhouse executable")
    ap.add_argument("--output", type=Path, required=True, help="new isolated output directory")
    args = ap.parse_args()
    fidelity, original = args.fidelity.resolve(), args.original_repo.resolve()
    binary, output = args.roundhouse.resolve(), args.output.resolve()
    lock = json.loads((fidelity / "SOURCE_LOCK.json").read_text())
    if lock.get("discourse_revision") != PIN:
        raise SystemExit(f"wrong lock pin: {lock.get('discourse_revision')}")
    rev = subprocess.check_output(["git", "-C", str(original), "rev-parse", "HEAD"], text=True).strip()
    if rev != PIN:
        raise SystemExit(f"original checkout is {rev}, expected {PIN}")
    locked = {item["path"]: item["sha256"] for item in lock["files"]}
    output.mkdir(parents=True, exist_ok=False)
    source_root = output / "input"
    source_root.mkdir()
    files = []
    for path in CHAIN:
        if path not in locked:
            raise SystemExit(f"missing source lock entry: {path}")
        upstream = subprocess.check_output(["git", "-C", str(original), "show", f"{PIN}:{path}"])
        copied = (fidelity / "source/discourse" / path).read_bytes()
        checkout = (original / path).read_bytes()
        expected = locked[path]
        if not (sha(upstream) == sha(copied) == sha(checkout) == expected):
            raise SystemExit(f"source byte/hash mismatch: {path}")
        destination = source_root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(upstream)
        files.append({"path": path, "sha256": expected, "bytes": len(upstream),
                      "source_span": {"start_byte": 0, "end_byte": len(upstream),
                                      "start_line": 1, "end_line": upstream.count(b"\n") + 1,
                                      "sha256": sha(upstream)},
                      "copied_sha256": sha(destination.read_bytes())})
    positive_source_checks = [
        ("lib/topic_query.rb", "def list_latest"),
        ("lib/topic_query.rb", "TopicList.new(filter, @user, topics, options.merge(@options))"),
        ("app/controllers/list_controller.rb", "TopicQuery.new(current_user, list_opts).public_send(\"list_#{filter}\")"),
        ("app/controllers/list_controller.rb", "define_method(filter) do |options = nil|"),
        ("lib/topic_list_responder.rb", "format.json { render_serialized(list, TopicListSerializer) }"),
        ("app/serializers/topic_list_serializer.rb", "has_many :topics, serializer: TopicListItemSerializer, embed: :objects"),
        ("app/serializers/topic_list_item_serializer.rb", "class TopicListItemSerializer"),
        ("lib/application_layout_preloader.rb", "SiteSetting.client_settings_json"),
    ]
    coverage = []
    for path, marker in positive_source_checks:
        data = (source_root / path).read_bytes()
        marker_bytes = marker.encode()
        offset = data.find(marker_bytes)
        if offset < 0:
            raise SystemExit(f"missing original chain anchor {path}: {marker}")
        coverage.append({"path": path, "anchor": marker, "start_byte": offset,
                         "end_byte": offset + len(marker_bytes),
                         "start_line": data[:offset].count(b"\n") + 1,
                         "sha256": sha(marker_bytes), "executed": False})
    (source_root / "original-input-manifest.json").write_text(json.dumps({
        "source_revision": PIN, "status": "exact_original_source_inputs_verified",
        "claim": "complete named application source input chain, not complete app boot or execution",
        "positive_source_chain_checks": coverage, "files": files,
        "unsupported_diagnostics_executed": False}, indent=2) + "\n")
    version = subprocess.check_output([str(binary), "--version"], text=True).strip()
    strict = _run_probe(binary, source_root, output, "strict", [])
    survey = _run_probe(binary, source_root, output, "survey", ["--survey", "--allow-unsupported"])
    strict_first = parse_strict_failure((output / strict["stderr"]).read_text(), source_root)
    parsed = survey["diagnostics"]
    inventory = {
        "source_revision": PIN, "roundhouse_version": version,
        "roundhouse_sha256": sha(binary.read_bytes()), "source_files": len(files),
        "source_bytes": sum(f["bytes"] for f in files), "source_inputs": files,
        "strict_ingest": {k: v for k, v in strict.items() if k != "diagnostics"},
        "strict_first_failure": strict_first,
        "survey": {k: v for k, v in survey.items() if k != "diagnostics"},
        "survey_diagnostic_count": len(parsed["diagnostics"]),
        "diagnostic_categories": parsed["diagnostic_categories"],
        "first_source_failure": parsed["first_source_failure"],
        "malformed_diagnostic_lines": parsed["malformed_lines"],
        "topic_list_responder_json_diagnostics": [d for d in parsed["diagnostics"]
            if d["source"] == "lib/topic_list_responder.rb" and "format.json" in d["message"]],
        "diagnostics_only": True, "survey_output_executed": False,
        "runtime_observations": [], "runtime_executed": False,
        "inventory_note": "Claims are derived only from diagnostics observed in this run; absent diagnostics produce empty/null fields.",
    }
    (output / "inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    print(json.dumps({"output": str(output), "source_files": len(files),
                      "source_bytes": inventory["source_bytes"], "roundhouse": version,
                      "strict_returncode": strict["returncode"],
                      "strict_first_failure": strict_first,
                      "survey_returncode": survey["returncode"],
                      "survey_diagnostic_count": inventory["survey_diagnostic_count"],
                      "diagnostic_categories": inventory["diagnostic_categories"],
                      "survey_output_executed": False}, indent=2))
    # Evidence is written before preserving any failed probe's nonzero status.
    return strict["returncode"] or survey["returncode"]

if __name__ == "__main__":
    raise SystemExit(main())
