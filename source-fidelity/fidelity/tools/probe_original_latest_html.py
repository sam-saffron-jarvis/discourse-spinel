#!/usr/bin/env python3
"""Original pinned HTML/frontend prerequisite ONLY; never native/page acceptance.

Use an isolated archive of the exact original source plus its genuinely built
frontend. All PG/Valkey/Vips guards remain in force; a CSS cache write or unknown
endpoint is an actual failure, never a reason to relax the guard.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from oracle_sandbox import ValkeySandbox
from verify import HERE, ROOT, PIN, Run, digest


def audit_source(root):
    records = []
    tree = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "ls-tree", "-rz", PIN])
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, kind, expected = metadata.decode().split()
        assert kind == "blob", f"unsupported source entry {raw_path!r}: {kind}"
        path = root / raw_path.decode()
        data = os.readlink(path).encode() if mode == "120000" else path.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        assert actual == expected, f"isolated original source changed: {raw_path!r}"
        records.append([raw_path.decode(), digest(data)])
    return {"pin": PIN, "matched_source_files": len(records),
            "path_sha256_aggregate": digest(json.dumps(records, sort_keys=True).encode())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True,
                        help="isolated original source archive WITH real frontend build, under fidelity/build")
    parser.add_argument("--prevent-ar-writes", action="store_true",
                        help="use actual Rails while_preventing_writes scope; original ReadOnlyError handling, no replaced callbacks")
    args = parser.parse_args()
    source = args.source_root.resolve()
    assert source.is_relative_to((HERE / "build").resolve()) and source != (ROOT / "discourse").resolve()
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = Run("probe-original-latest-html")
    run.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", LOAD_PLUGINS="0", LEFTHOOK="0")
    run.env["FIDELITY_HTML_PREVENT_AR_WRITES"] = "1" if args.prevent_ar_writes else "0"
    run.evidence.update(stage=__doc__, actual_ar_write_prevention_profile=args.prevent_ar_writes,
                        native_html_executed=False, browser_rendered=False,
                        page_accepted=False, broader019_accepted=False)
    sandbox = ValkeySandbox(run.path / "original-cache")
    code = 1
    try:
        run.provenance()
        run.evidence["original_source_before"] = audit_source(source)
        manifest = source / "frontend/discourse/dist/manifest/manifest.json"
        run.evidence["actual_frontend_manifest"] = {"path": str(manifest), "sha256": digest(manifest.read_bytes())}
        # Read the actual reference repository's Git metadata; do not freeze a
        # captured SHA into GitUtils or let a gitless archive report Fidelity's SHA.
        git_dir = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "rev-parse", "--absolute-git-dir"], text=True).strip()
        run.env.update(GIT_DIR=git_dir, GIT_WORK_TREE=str(source),
                       FIDELITY_VIPS_ORIGINAL_APPLICATION_ROOT=str(source),
                       FIDELITY_VIPS_LOG=str(run.path / "original-readonly-vips.jsonl"),
                       FIDELITY_REJECTION_LOG=str(run.path / "original-policy-rejections.jsonl"),
                       FIDELITY_ORACLE_PHASE="original-built-frontend-html",
                       FIDELITY_HTML_SOURCE_PIN=PIN, FIDELITY_HTML_OUTPUT_DIRECTORY=str(run.path))
        with sandbox:
            run.env.update(sandbox.environment)
            code, _ = run.command("original-html", ["bundle", "exec", "ruby", HERE / "tools/latest_html_reference_probe.rb"],
                                  cwd=source, timeout=180, check=False)
        run.evidence["original_source_after"] = audit_source(source)
        assert run.evidence["original_source_before"] == run.evidence["original_source_after"]
        run.evidence.update(status="ORIGINAL_HTML_PREREQUISITE_ONLY" if code == 0 else "FAILED_ORIGINAL_HTML_PREREQUISITE",
                            original_html_returncode=code)
    except BaseException as error:
        run.evidence.update(status="FAILED_ORIGINAL_HTML_PREREQUISITE", error=repr(error))
        raise
    finally:
        run.evidence["owned_cache_cleanup_complete"] = sandbox.cleanup_complete
        run.save()
        print(run.path)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
