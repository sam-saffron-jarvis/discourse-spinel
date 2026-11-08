#!/usr/bin/env python3
"""Archive the canonical guarded keyword/repeated-accessor control, never framework boot."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_MACRO = "2d138af1438e8f9091d8ec9e0ed350c067be4748c887cd70cd28fecafaceba60"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("keyword", "repeat"), default="keyword")
    case = parser.parse_args().case
    test = "native_keyword_argument_keeps_evaluation_and_mutable_identity" if case == "keyword" else "native_identical_accessor_reinstallation_keeps_all_real_hooks"
    expected = b"keyword argument capture PASS\n" if case == "keyword" else b"repeated definition events PASS\n"
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    target = ROOT / "fidelity/build" / ("probe-mattr-" + case + "-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    target.mkdir(parents=True)
    env = dict(os.environ, CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", ROUNDHOUSE_KEEP_EMITTED="1")
    env["PATH"] = str(ROOT / "spinel/bin") + os.pathsep + env["PATH"]
    evidence = {"scope": f"guarded {case} capability ONLY", "broader019_accepted": False,
                "native_seedfu_executed": False, "block_defaults_accepted": False, "status": "started", "commands": []}

    def command(label, args, cwd=ROOT):
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, capture_output=True, timeout=300)
        (target / (label + ".stdout")).write_bytes(result.stdout)
        (target / (label + ".stderr")).write_bytes(result.stderr)
        evidence["commands"].append({"label": label, "argv": list(map(str, args)), "cwd": str(cwd), "returncode": result.returncode})
        assert result.returncode == 0, f"{label} failed; raw evidence retained"
        return result

    try:
        before = set(Path(tempfile.gettempdir()).glob("roundhouse-emit-and-run-*/emitted"))
        command("canonical-native-test", ["cargo", "test", "--manifest-path", "roundhouse/Cargo.toml", "--test", "ordered_mattr_events",
            test, "--", "--ignored", "--exact", "--nocapture"])
        after = set(Path(tempfile.gettempdir()).glob("roundhouse-emit-and-run-*/emitted"))
        candidates = [path for path in after - before if (path / "contract").is_file() and (path.parent / "app/lib/ordered_mattr.rb").is_file()]
        assert len(candidates) == 1, "exactly one new canonical native artifact required"
        artifact = candidates[0]
        assert (artifact / "contract").read_bytes()[:4] == b"\x7fELF"
        original = artifact.parent / "app/lib/ordered_mattr.rb"
        assert original.is_file(), "canonical original subject not retained"
        consumer = (artifact / "contract.rb").read_text().split("\n", 1)[1]
        macro = command("original-macro", ["ruby", "-rdigest", "-rjson", "-ractive_support/core_ext/module/attribute_accessors", "-e",
            'p = Module.instance_method(:mattr_accessor).source_location.first; puts JSON.generate(path: p, sha256: Digest::SHA256.file(p).hexdigest)'])
        source = json.loads(macro.stdout)
        assert source["sha256"] == EXPECTED_MACRO
        evidence["genuine_original_macro"] = source
        original_run = command("original", ["ruby", "--enable-frozen-string-literal", "-ractive_support/core_ext/module/attribute_accessors", "-e",
            "load ARGV.fetch(0)\n" + consumer, original])
        # The generated full boot includes native-only database FFI, outside
        # this no-service library capability. Use one NEW test consumer for
        # BOTH engines, without modifying any generated application/runtime file.
        shared = artifact / f"{case}-shared.rb"
        shared.write_text('require_relative "app/models"\n' + consumer)
        command("compile-same-lowered", [ROOT / "spinel/bin/spinel", "--jobs=4", "--rbs", ".", shared.name, "-o", f"{case}-shared"], artifact)
        files = {str(path.relative_to(artifact)): sha(path) for path in sorted(artifact.rglob("*.rb"))}
        lowered = command("same-lowered-cruby", ["ruby", "--enable-frozen-string-literal", shared.name], artifact)
        native = command("same-lowered-native", [artifact / f"{case}-shared"], artifact)
        assert original_run.stdout == lowered.stdout == native.stdout == expected
        assert files == {str(path.relative_to(artifact)): sha(path) for path in sorted(artifact.rglob("*.rb"))}
        shutil.copytree(artifact, target / "snapshot")
        shutil.copyfile(original, target / "original-subject.rb")
        evidence["artifact"] = {"executed_directory": str(artifact), "snapshot": "snapshot", "elf_sha256": sha(artifact / f"{case}-shared"),
            "ruby_files_unchanged": True, "same_lowered_cruby_native_vs_original": True, "ruby_file_hashes": files,
            "rbs_file_hashes": {str(path.relative_to(artifact)): sha(path) for path in sorted(artifact.rglob("*.rbs"))},
            "original_subject_sha256": sha(original)}
        evidence["revisions"] = {repo: command(repo + "-head", ["git", "-C", repo, "rev-parse", "HEAD"]).stdout.decode().strip() for repo in ("roundhouse", "spinel", "fidelity")}
        if shutil.which("strace"):
            trace = command("native-process", ["strace", "-f", "-e", "trace=process", "-o", target / "native.process", artifact / f"{case}-shared"], artifact)
            assert trace.stdout == native.stdout
            text = (target / "native.process").read_text()
            assert text.count("execve(") == 1 and not any(name + "(" in text for name in ("clone", "clone3", "fork", "vfork"))
            evidence["direct_native_process_only"] = True
        evidence["status"] = f"passed_{case}_capability_NOT_019"
    except Exception as error:
        evidence.update(status="failed", error=repr(error))
        raise
    finally:
        (target / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Evidence: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
