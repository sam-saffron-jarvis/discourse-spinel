#!/usr/bin/env python3
"""Retain the finite native file-program capability control, never SeedFu admission.

The canonical subjects and assertions live in Roundhouse's native_file_programs
suite. This runner archives that suite's actual original/lowered/native files
and output instead of maintaining a second version of the loader experiment.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "fidelity"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    target = HERE / "build" / ("probe-native-file-programs-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    target.mkdir(parents=True)
    env = dict(os.environ, CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", ROUNDHOUSE_KEEP_EMITTED="1")
    env["PATH"] = str(ROOT / "spinel/bin") + os.pathsep + env["PATH"]
    evidence = {"scope": "finite native file-program capability ONLY; original reduced subject, not application source",
                "broader019_accepted": False, "native_seedfu_executed": False,
                "native_activation_accepted": False, "status": "started", "commands": []}

    def command(label, args, cwd=ROOT, timeout=300):
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, capture_output=True, timeout=timeout)
        (target / (label + ".stdout")).write_bytes(result.stdout)
        (target / (label + ".stderr")).write_bytes(result.stderr)
        evidence["commands"].append({"label": label, "argv": list(map(str, args)), "cwd": str(cwd), "returncode": result.returncode})
        if result.returncode:
            raise RuntimeError(f"{label} failed ({result.returncode}); raw output retained")
        return result

    try:
        for repo in ("roundhouse", "spinel"):
            head = command(repo + "-head", ["git", "-C", repo, "rev-parse", "HEAD"]).stdout.decode().strip()
            status = command(repo + "-status", ["git", "-C", repo, "status", "--porcelain"]).stdout.decode()
            command(repo + "-diff", ["git", "-C", repo, "diff", "HEAD"])
            evidence[repo] = {"head": head, "status": status}
        result = command("capability-tests", ["cargo", "test", "--manifest-path", "roundhouse/Cargo.toml", "--test", "native_file_programs", "--", "--nocapture", "--test-threads=1"])
        paths = re.findall(r"^FINITE_FILE_PROGRAM_EVIDENCE=(.+)$", (result.stdout + result.stderr).decode(), re.M)
        assert len(paths) == 1, "exactly one executed positive control must be retained"
        artifact = Path(paths[0])
        assert (artifact / "probe").read_bytes()[:4] == b"\x7fELF"
        outputs = [(artifact / name).read_bytes() for name in ("original.stdout", "lowered.stdout", "native.stdout")]
        assert outputs[0] == outputs[1] == outputs[2] == b"cycle|value1|load failed|value2\n"
        shutil.copytree(artifact, target / "snapshot")
        evidence["artifact"] = {"executed_directory": str(artifact), "snapshot": "snapshot",
            "note": "Snapshot preserves absolute feature literals from this execution; rerun the suite to generate a relocated experiment.",
            "elf_sha256": digest(artifact / "probe"), "same_lowered_cruby_native_vs_original": True,
            "files": {str(path.relative_to(artifact)): digest(path) for path in sorted(artifact.rglob("*")) if path.is_file()}}
        integrated = re.findall(r"^ORDERED_MATTR_FILE_PROGRAM_EVIDENCE=(.+)$", (result.stdout + result.stderr).decode(), re.M)
        assert len(integrated) == 1, "the integrated ordered plain-mattr control must execute"
        ordered = Path(integrated[0])
        ordered_outputs = [(ordered / name).read_bytes() for name in ("original.stdout", "lowered.stdout", "native.stdout")]
        assert ordered_outputs[0] == ordered_outputs[1] == ordered_outputs[2] == outputs[0]
        shutil.copytree(ordered, target / "ordered-mattr-snapshot")
        evidence["ordered_plain_mattr_integrated"] = {"executed_directory": str(ordered), "snapshot": "ordered-mattr-snapshot",
            "scope": "nil seed observed before explicit false, both method sides, composed with lazy/cache/failure/retry; NOT default/block/repeated-native admission",
            "files": {str(path.relative_to(ordered)): digest(path) for path in sorted(ordered.rglob("*")) if path.is_file()}}
        evidence["input_hashes"] = {str(path.relative_to(ROOT)): digest(path) for path in [
            ROOT / "roundhouse/src/ingest/ordered_mattr.rs", ROOT / "roundhouse/tests/ordered_mattr_events.rs",
            ROOT / "roundhouse/tests/native_file_programs.rs", ROOT / "roundhouse/src/lower/file_programs.rs",
            ROOT / "roundhouse/src/project/file_programs.rs", ROOT / "roundhouse/src/project.rs", ROOT / "spinel/bin/spinel"]}
        if shutil.which("strace"):
            traced = command("native-process-trace", ["strace", "-f", "-e", "trace=process", "-o", target / "native.process", artifact / "probe"], cwd=artifact)
            assert traced.stdout == outputs[0]
            trace = (target / "native.process").read_text()
            assert len(re.findall(r"\bexecve\(", trace)) == 1, "native control launched a child executable"
            assert not re.search(r"\b(?:clone|clone3|fork|vfork)\(", trace), "native control created a child process/thread"
            evidence["direct_native_process_only"] = True
        evidence["status"] = "passed_bounded_capability_NOT_019"
    except Exception as error:
        evidence.update(status="failed", error=repr(error))
        raise
    finally:
        (target / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Evidence: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
