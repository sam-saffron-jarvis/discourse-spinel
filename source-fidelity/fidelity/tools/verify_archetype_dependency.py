#!/usr/bin/env python3
"""Original Archetype/real serialization-source dependency ONLY, not activation."""
import argparse
import json
from pathlib import Path
import shutil
import sys

from verify import Run, ROOT, HERE, digest, equal_records
from probe_original_query import audit_projection, diagnostics
from archetype_dependency import materialize


class ArchetypeRun(Run):
    def __init__(self):
        super().__init__("verify-archetype-dependency")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", FIDELITY_WRONG_ARCHETYPE="0")
        self.evidence.update(stage="complete original registry205 Archetype + genuine serialization-source dependency ONLY",
                             broader019_accepted=False, native_activation_accepted=False, transformations=[])

    def build(self, compiler):
        app = self.path / "input"
        materialize(HERE, app, digest)
        for name, text in {"db/schema.rb": "ActiveRecord::Schema.define do\nend\n", "config/routes.rb": "Rails.application.routes.draw do\nend\n"}.items():
            target = app / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.evidence["input_map"] = audit_projection(app)
        self.command("strict", [compiler, "--target", "spinel", app, "-o", self.path / "emitted"], timeout=120)
        shutil.copyfile(HERE / "test/archetype_dependency_probe.rb", self.path / "probe.rb")
        (self.path / "entry.rb").write_text('require "json"\nrequire_relative "emitted/runtime/active_support_ext"\nrequire_relative "emitted/app/models"\nrequire_relative "probe"\n')
        self.command("native-compile", [ROOT / "spinel/bin/spinel", "--jobs=4", "--rbs", self.path / "emitted", self.path / "entry.rb", "-o", self.path / "probe"], timeout=120)
        assert (self.path / "probe").read_bytes()[:4] == bytes.fromhex("7f454c46")
        self.evidence["elf_sha256"] = digest((self.path / "probe").read_bytes())
        self.evidence["same_lowered_hashes"] = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
        self.save()

    def execute(self):
        self.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / "native.trace", self.path / "probe"], timeout=30)
        trace = (self.path / "native.trace").read_text()
        assert trace.count("execve(") == 1 and "connect(" not in trace
        self.evidence["native_no_child_or_network"] = True
        self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", self.path / "entry.rb"], cwd=ROOT / "discourse", timeout=30)
        original = '\n'.join(['require "json"', 'require "active_model/serialization"', 'require "active_support/core_ext/object/blank"',
                              f'require {json.dumps(str(HERE / "source/discourse/lib/archetype.rb"))}',
                              f'load {json.dumps(str(self.path / "probe.rb"))}', ''])
        self.command("original-prefix", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", "-e", original], cwd=ROOT / "discourse", timeout=30)
        equal_records(self.records("native"), self.records("compat"))
        equal_records(self.records("native"), self.records("original-prefix"))
        assert self.records("native")[0]["rows"], "original default declarations did not execute"
        try:
            self.env["FIDELITY_WRONG_ARCHETYPE"] = "1"
            self.command("native-wrong", [self.path / "probe"], timeout=30)
        finally:
            self.env["FIDELITY_WRONG_ARCHETYPE"] = "0"
        try:
            equal_records(self.records("native-wrong"), self.records("native"))
        except AssertionError:
            self.evidence["native_negative_control"] = "detected omission of original default registration using the real original deregister API"
        else:
            raise AssertionError("native wrong declaration state was accepted")
        self.save()

    def measure_registry(self, compiler):
        app = self.path / "full-registry-input"
        shutil.copytree(self.path / "input", app)
        maps = json.loads((app / "projection-map.json").read_text())
        for original, generated in (
            ("lib/discourse_plugin_registry.rb", "app/models/discourse_plugin_registry.rb"),
            ("lib/vendored_assets.rb", "app/models/vendored_assets.rb"),
        ):
            source = HERE / "source/discourse" / original
            target = app / generated
            shutil.copyfile(source, target)
            data = source.read_bytes()
            sha = digest(data)
            maps.append({"source": original, "generated": generated,
                         "source_sha256": sha, "generated_sha256": sha,
                         "selected_spans": [{"start_byte": 0, "end_byte": len(data), "text_sha256": sha}],
                         "limitation": "complete original dependency measurement ONLY; not full-registry execution"})
        (app / "projection-map.json").write_text(json.dumps(maps, indent=2) + "\n")
        self.evidence["registry_input_map"] = audit_projection(app)
        source = HERE / "source/discourse/lib/discourse_plugin_registry.rb"
        code, _ = self.command("registry-strict", [compiler, "--target", "spinel", app, "-o", self.path / "registry-emitted"], check=False, timeout=120)
        self.evidence["complete_registry_measurement"] = {"source": "lib/discourse_plugin_registry.rb", "sha256": digest(source.read_bytes()),
            "strict_returncode": code, "diagnostics": diagnostics((self.path / "registry-strict.stderr").read_text(), app),
            "executed": False, "warning": "remaining dependency errors are retained; no first-class HIA class value admitted"}
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", HERE / "tools/archetype_dependency_oracle_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        for name in ("native", "compat", "original-prefix"):
            equal_records(self.records(name), oracle)
        return {"native_equal": True, "compat_equal": True, "original_prefix_equal": True,
                "scope": "original Archetype defaults/lifecycle/default serialization ONLY; not native activation/settings/query/page"}

    def audit(self):
        audit_projection(self.path / "input")
        if (self.path / "full-registry-input").exists():
            audit_projection(self.path / "full-registry-input")
        for name, sha in self.evidence.get("same_lowered_hashes", {}).items():
            assert digest((self.path / "emitted" / name).read_bytes()) == sha
        self.provenance()
        sandbox = self.evidence.get("oracle_sandbox")
        if sandbox:
            assert sandbox["status"] == "stopped" and sandbox["cleanup"] == "child_exited"
            self.evidence["oracle_cleanup_verified"] = True
        self.evidence["post_execution_hashes_verified"] = True
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "roundhouse/target/release/roundhouse")
    args = parser.parse_args()
    import os
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = ArchetypeRun()
    try:
        run.provenance()
        run.build(args.compiler.resolve())
        try:
            run.execute()
            run.env["FIDELITY_EXTRA_ORIGINAL_INPUTS"] = json.dumps(["lib/archetype.rb"])
            run.env["FIDELITY_SERIALIZATION_SHA256"] = run.evidence["framework_sources"][0]["files"][0]["sha256"]
            run.oracle()
            run.measure_registry(args.compiler.resolve())
        finally:
            run.audit()
        run.evidence["status"] = "passed_original_archetype_dependency_ONLY"
        run.save()
        print(f"PASS original Archetype dependency ONLY; native activation/019 NOT ACCEPTED. Evidence: {run.path}")
        return 0
    except Exception as error:
        import traceback
        traceback.print_exc()
        run.evidence.update(status="failed", error=repr(error))
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
