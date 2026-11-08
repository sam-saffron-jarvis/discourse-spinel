#!/usr/bin/env python3
"""Archive a reduced original ActiveSupport / shared-IR Ruby singleton control.

NOT a native forwarding capability or core getter/provider/page implementation.
The native carrier refusal is intentionally retained and checked separately.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-diagnostic", action="store_true",
                        help="also compile the complete shared-IR subject with the genuine AS runtime; never grants admission")
    args = parser.parse_args()
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    target = ROOT / "fidelity/build" / datetime.now().strftime("probe-core-singleton-delegate-%Y%m%d-%H%M%S")
    target.mkdir()
    env = dict(os.environ, CARGO_BUILD_JOBS="4", ROUNDHOUSE_SINGLETON_DELEGATE_ARCHIVE=str(target / "subject"))
    evidence = {"scope": "reduced original ActiveSupport / shared-IR Ruby receiver/ABI/error/callback control ONLY",
                "native_carrier_accepted": False, "core_getter_executed": False,
                "core_page_accepted": False, "full_plugin019_accepted": False,
                "commands": [], "status": "started"}

    def command(label, argv, require_success=True):
        result = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, timeout=300)
        (target / f"{label}.stdout").write_bytes(result.stdout)
        (target / f"{label}.stderr").write_bytes(result.stderr)
        evidence["commands"].append({"label": label, "argv": list(map(str, argv)), "returncode": result.returncode})
        if require_success:
            assert result.returncode == 0, f"{label} failed; evidence retained"
        return result

    try:
        command("canonical-source-and-negative-tests", ["cargo", "test", "--manifest-path", "roundhouse/Cargo.toml",
                "--lib", "ingest::delegate::singleton_tests::", "--", "--nocapture"])
        subject = target / "subject"
        before = {str(path.relative_to(subject)): sha(path) for path in subject.iterdir()}
        original = command("original", ["ruby", "--enable-frozen-string-literal", subject / "original.rb"])
        lowered = command("same-shared-ir-ruby", ["ruby", "--enable-frozen-string-literal", subject / "lowered.rb"])
        assert original.stdout == lowered.stdout == (subject / "original.stdout").read_bytes() == (subject / "lowered.stdout").read_bytes()
        assert before == {str(path.relative_to(subject)): sha(path) for path in subject.iterdir()}
        evidence["subject_sha256"] = before
        for repo in ("roundhouse", "spinel", "fidelity"):
            evidence[repo] = {"head": command(repo + "-head", ["git", "-C", repo, "rev-parse", "HEAD"]).stdout.decode().strip(),
                              "status": command(repo + "-status", ["git", "-C", repo, "status", "--porcelain"]).stdout.decode()}
        evidence["ruby_version"] = command("ruby-version", ["ruby", "--version"]).stdout.decode().strip()
        source = command("active-support-source", ["ruby", "-rjson", "-rdigest", "-ractive_support/core_ext/module/delegation", "-e",
            's=Gem::Specification.find_by_name("activesupport"); puts JSON.generate({version:s.version.to_s,files:%w[active_support/delegation.rb active_support/core_ext/module/delegation.rb].to_h{|f| p=File.join(s.full_gem_path,"lib",f);[f,Digest::SHA256.file(p).hexdigest]}})'])
        evidence["original_macro_source"] = json.loads(source.stdout)
        if args.native_diagnostic:
            # Keep EVERY method/callback/driver assertion in the shared-IR
            # subject. In particular, do not drop allow_nil, full error strings,
            # descriptors or nonlocal returns to manufacture a native pass.
            as_root = command("active-support-root", ["ruby", "-e",
                'print Gem::Specification.find_by_name("activesupport").full_gem_path']).stdout.decode()
            as_lib = Path(as_root) / "lib"
            runtime_sources = [as_lib / "active_support/delegation.rb",
                               as_lib / "active_support/core_ext/module/delegation.rb"]
            runtime_hashes = {str(path): sha(path) for path in runtime_sources}
            compiler = Path(os.environ.get("SPINEL", str(ROOT / "spinel/bin/spinel"))).resolve()
            candidate = target / "native-candidate"
            diagnostic = {"scope": "complete reduced shared-IR subject + genuine AS runtime diagnostic ONLY",
                          "compiler_sha256": sha(compiler), "runtime_source_sha256": runtime_hashes,
                          "native_carrier_accepted": False, "core_getter_executed": False}
            evidence["native_diagnostic"] = diagnostic
            built = command("native-compile", [compiler, "--load-model=graph", "--jobs=4",
                            "-I", as_lib, subject / "lowered.rb", "-o", candidate], require_success=False)
            diagnostic["compile_returncode"] = built.returncode
            diagnostic["refused_without_binary"] = built.returncode != 0 and not candidate.exists()
            diagnostic["status"] = "compiler_refused_or_failed_not_admitted"
            if built.returncode == 0:
                ran = command("native-run", [candidate], require_success=False)
                diagnostic.update(run_returncode=ran.returncode,
                                  stdout_matches_original=ran.stdout == original.stdout)
                diagnostic["status"] = ("reduced_runtime_matched_NOT_admitted"
                                        if ran.returncode == 0 and ran.stdout == original.stdout
                                        else "reduced_runtime_FAILED_not_admitted")
            # A successful reduced compile/run would still not prove source
            # dispatch closure or the actual core main/patch feature lifetimes.
            assert runtime_hashes == {str(path): sha(path) for path in runtime_sources}
            assert before == {str(path.relative_to(subject)): sha(path) for path in subject.iterdir()}
            diagnostic["source_hashes_unchanged"] = True
        evidence["status"] = "passed_source_prerequisite_ONLY_native_carrier_remains_refused"
    except Exception as error:
        evidence.update(status="failed_source_prerequisite", error=repr(error))
        raise
    finally:
        (target / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Evidence: {target}")


if __name__ == "__main__":
    main()
