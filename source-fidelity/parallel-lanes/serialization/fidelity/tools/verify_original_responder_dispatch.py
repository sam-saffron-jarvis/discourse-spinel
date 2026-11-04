#!/usr/bin/env python3
"""Compile an exact original TopicListResponder method projection and inspect dispatch.

The method body is copied byte-for-byte from the pinned original. A tiny test-only
controller consumer supplies request context; it does not replace the responder,
query, serializer, permissions, or settings. Output is inspected only, never run.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
SOURCE = "lib/topic_list_responder.rb"

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fidelity", type=Path, required=True)
    ap.add_argument("--roundhouse", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    fidelity, binary, output = args.fidelity.resolve(), args.roundhouse.resolve(), args.output.resolve()
    lock = json.loads((fidelity / "SOURCE_LOCK.json").read_text())
    item = next((x for x in lock["files"] if x["path"] == SOURCE), None)
    if lock.get("discourse_revision") != PIN or item is None:
        raise SystemExit("original responder is not locked at expected pin")
    original = (fidelity / "source/discourse" / SOURCE).read_bytes()
    if digest(original) != item["sha256"]:
        raise SystemExit("original responder copy differs from SOURCE_LOCK")
    output.mkdir(parents=True, exist_ok=False)
    source_root = output / "input"
    project = subprocess.run(["ruby", str(fidelity / "tools/project_original_responder.rb"),
                              str(fidelity / "source/discourse"), str(source_root)],
                             text=True, capture_output=True)
    (output / "projection.stdout").write_text(project.stdout)
    (output / "projection.stderr").write_text(project.stderr)
    if project.returncode:
        return project.returncode
    projection = json.loads((source_root / "responder-projection.json").read_text())
    generated = source_root / projection["generated"]
    projected = generated.read_bytes()
    for span in projection["selected_spans"]:
        start, end = span["start_byte"], span["end_byte"]
        if original[start:end] != projected[start:end] or digest(projected[start:end]) != span["sha256"]:
            raise SystemExit(f"original source span changed: {span['role']}")
    # This consumer only invokes the exact original responder method. It does
    # not provide replacement query/serializer/settings/permission semantics.
    harness_files = {
        "app/controllers/application_controller.rb": "class ApplicationController < ActionController::Base\nend\n",
        "app/controllers/list_controller.rb": (
            "class ListController < ApplicationController\n"
            "  include TopicListResponder\n\n"
            "  def index\n"
            "    respond_with_list(@list)\n"
            "  end\n"
            "end\n"),
        "config/routes.rb": 'Rails.application.routes.draw do\n  get "/latest" => "list#index"\nend\n',
    }
    for path, body in harness_files.items():
        target = source_root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body)
    command = [str(binary), "--target", "spinel", "--allow-unsupported",
               str(source_root), "-o", str(output / "emitted")]
    proc = subprocess.run(command, text=True, capture_output=True)
    (output / "roundhouse.stdout").write_text(proc.stdout)
    (output / "roundhouse.stderr").write_text(proc.stderr)
    emitted_candidates = list((output / "emitted/app/controllers").glob("list_controller.rb"))
    emitted_source = emitted_candidates[0].read_text() if emitted_candidates else ""
    branch_retained = ("request_format == :json" in emitted_source and
                       "render_serialized(list, TopicListSerializer)" in emitted_source)
    html_body_retained = ("localize_topic_list_content(list)" in emitted_source and
                         "store_preloaded(" in emitted_source and "@list = list" in emitted_source)
    json_dropped = any("format.json" in line and "dropped" in line
                       for line in proc.stderr.splitlines())
    evidence = {
        "source_revision": PIN, "source_path": SOURCE, "source_sha256": item["sha256"],
        "projection": projection, "harness_files": sorted(harness_files),
        "command": command, "returncode": proc.returncode,
        "emitted_controller": "emitted/app/controllers/list_controller.rb" if emitted_source else None,
        "original_format_json_branch_retained_in_request_dispatch": branch_retained,
        "original_html_branch_side_effects_retained": html_body_retained,
        "format_json_drop_diagnostic": json_dropped,
        "json_diagnostics": [line for line in proc.stderr.splitlines()
                             if "format.json" in line or "render_serialized" in line],
        "output_executed": False,
        "unsupported_mode": "--allow-unsupported, no --survey; possible unsupported constructs are warnings, output is inspected only",
        "scope_limit": "original responder method only; synthetic controller consumer; not serializer/runtime parity or full app boot",
        "remaining_render_serialized_contract": "original ApplicationController#render_serialized/serialize_data/render_json_dump and TopicListSerializer runtime are not included/executed by this probe",
    }
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({k: evidence[k] for k in ("returncode", "original_format_json_branch_retained_in_request_dispatch",
                  "format_json_drop_diagnostic", "output_executed", "remaining_render_serialized_contract")}, indent=2))
    if proc.returncode:
        return proc.returncode
    if not branch_retained or not html_body_retained or json_dropped:
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
