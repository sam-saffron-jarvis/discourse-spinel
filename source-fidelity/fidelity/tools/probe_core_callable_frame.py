#!/usr/bin/env python3
"""Archive reduced core reader callable or model-owner prerequisites ONLY.

This reduced compiler control is NOT a SiteSetting/provider implementation or
native core /latest. It preserves real method formals, captures, installation
hooks and Method arity; original source/settings values are never synthesized.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--model-class", action="store_true", help="prove the reduced direct-ActiveRecord model owner instead")
    group.add_argument("--nested-reader", action="store_true", help="prove the reduced per-site memoized extension reader")
    group.add_argument("--engine-context", action="store_true", help="prove reduced source-gem engine ownership, constructor and file effects")
    group.add_argument("--namespace-features", action="store_true", help="prove source-owned namespace helper features, not provider/page execution")
    args = parser.parse_args()
    prefix = "probe-core-model-owner" if args.model_class else "probe-core-callable-frame"
    binary = "model_class_setting" if args.model_class else "nil_optional"
    test = "source_model_class_owned_definition_runs_natively" if args.model_class else "nil_optional_definition_method_frame_runs_natively"
    suite = "runtime_definition_family"
    source_name = "app/app/models/model_class_runtime_settings.rb" if args.model_class else "app/lib/runtime_value_family.rb"
    driver = ("ModelClassRuntimeSettings" if args.model_class else "RuntimeValueFamily") + ".exercise(false)\n"
    arguments = []
    expected = b"model-owned runtime class setting PASS\n" if args.model_class else b"runtime family event PASS\n"
    if args.nested_reader:
        prefix, binary = "probe-core-nested-reader", "extension"
        suite, test = "runtime_definition_module_extension", "real_extension_callback_and_class_load_definitions_run_natively"
        source_name = "app/lib/extended_setting_owner.rb"
        driver, arguments = "ExtendedSettingOwner.exercise(ARGV.fetch(0))\n", ["runtime_choice"]
        expected = b"module extension runtime family PASS\n"
    if args.engine_context:
        prefix, binary = "probe-core-engine-context", "engine_dependency"
        suite, test = "source_gem_engine_context", "source_runtime_inventory_runs_natively"
        source_name = "app/lib/engine_dependency_consumer.rb"
        driver, expected = "EngineDependencyConsumer.exercise\n", b"engine source dependency PASS\n"
    if args.namespace_features:
        prefix, binary = "probe-core-namespace-features", "namespace_feature"
        suite, test = "source_namespace_features", "namespace_wrappers_preserve_original_features_natively"
        source_name = "app/lib/namespace_feature_consumer.rb"
        driver, expected = "NamespaceFeatureConsumer.exercise\n", b"source namespace features PASS\n"
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    target = ROOT / "fidelity/build" / datetime.now().strftime(prefix + "-%Y%m%d-%H%M%S")
    target.mkdir(parents=True)
    env = dict(os.environ, CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", ROUNDHOUSE_KEEP_EMITTED="1")
    env["PATH"] = str(ROOT / "spinel/bin") + os.pathsep + env["PATH"]
    evidence = {"scope": ("reduced source-owned namespace feature/lexical/binding proof ONLY" if args.namespace_features else "reduced source-gem engine ownership/constructor/file-effect proof ONLY" if args.engine_context else "reduced per-site memoized extension reader ONLY" if args.nested_reader else "reduced direct-AR model class owner ONLY" if args.model_class else "reduced nil-optional zero-argument method invocation/frame capability ONLY"),
                "core_getter_executed": False, "core_page_accepted": False, "full_plugin019_accepted": False,
                "commands": [], "status": "started"}

    def command(label, args, cwd=ROOT):
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, capture_output=True, timeout=180)
        (target / (label + ".stdout")).write_bytes(result.stdout)
        (target / (label + ".stderr")).write_bytes(result.stderr)
        evidence["commands"].append({"label": label, "argv": list(map(str, args)), "cwd": str(cwd), "returncode": result.returncode})
        assert result.returncode == 0, f"{label} failed; raw evidence retained"
        return result

    try:
        before = set(Path(tempfile.gettempdir()).glob("roundhouse-emit-and-run-*/emitted"))
        command("canonical-native-test", ["cargo", "test", "--manifest-path", "roundhouse/Cargo.toml", "--test", suite,
                test, "--", "--ignored", "--exact", "--nocapture"])
        after = set(Path(tempfile.gettempdir()).glob("roundhouse-emit-and-run-*/emitted"))
        candidates = [path for path in after - before if (path / binary).is_file()]
        assert len(candidates) == 1
        artifact = candidates[0]
        assert (artifact / binary).read_bytes()[:4] == b"\x7fELF"
        source = artifact.parent / source_name
        before_files = {str(path.relative_to(artifact)): sha(path) for path in sorted(artifact.rglob("*.rb"))}
        original_options = ["-ractive_record"] if args.model_class else []
        if args.engine_context or args.namespace_features:
            gem = "namespace_feature" if args.namespace_features else "engine_dependency"
            original_lib = artifact.parent / f"app/vendor/bundle/ruby/4.0.0/gems/{gem}-1.0/lib"
            original_options = ["-I", str(original_lib), "-r" + gem]
            original_files = {str(path.relative_to(original_lib)): sha(path) for path in original_lib.rglob("*.rb")}
        original = command("original", ["ruby", "--enable-frozen-string-literal", *original_options, "-e", source.read_text() + "\n" + driver, *arguments])
        lowered = command("same-lowered-cruby", ["ruby", "--enable-frozen-string-literal", binary + ".rb", *arguments], artifact)
        native = command("same-lowered-native", [artifact / binary, *arguments], artifact)
        assert original.stdout == lowered.stdout == native.stdout == expected
        assert before_files == {str(path.relative_to(artifact)): sha(path) for path in sorted(artifact.rglob("*.rb"))}
        shutil.copytree(artifact, target / "snapshot")
        shutil.copyfile(source, target / "original-subject.rb")
        if args.engine_context or args.namespace_features:
            assert original_files == {str(path.relative_to(original_lib)): sha(path) for path in original_lib.rglob("*.rb")}
            shutil.copytree(original_lib, target / "original-lib")
            evidence["original_gem_library_sha256"] = original_files
        evidence["artifact"] = {"elf_sha256": sha(artifact / binary), "original_sha256": sha(source),
            "same_lowered_cruby_native_vs_original": True,
            "files": {str(path.relative_to(artifact)): sha(path) for path in sorted(artifact.rglob("*")) if path.is_file()}}
        for repo in ("roundhouse", "spinel", "fidelity"):
            evidence[repo] = {"head": command(repo + "-head", ["git", "-C", repo, "rev-parse", "HEAD"]).stdout.decode().strip(),
                              "status": command(repo + "-status", ["git", "-C", repo, "status", "--porcelain"]).stdout.decode()}
        if shutil.which("strace"):
            command("native-process", ["strace", "-f", "-e", "trace=process,connect", "-o", target / "native.trace", artifact / binary, *arguments], artifact)
            trace = (target / "native.trace").read_text()
            assert trace.count("execve(") == 1 and "connect(" not in trace
            assert not any(name + "(" in trace for name in ("clone", "clone3", "fork", "vfork"))
            evidence["direct_native_only_no_service"] = True
        evidence["status"] = "passed_callable_prerequisite_ONLY_not_core_getter_or_page"
    except Exception as error:
        evidence.update(status="failed_callable_prerequisite", error=repr(error))
        raise
    finally:
        (target / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Evidence: {target}")


if __name__ == "__main__":
    main()
