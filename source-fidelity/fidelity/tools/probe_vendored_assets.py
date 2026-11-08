#!/usr/bin/env python3
"""Measure original registry279 VendoredAssets path values, never normalize them."""
import argparse
import json
from pathlib import Path
import shutil
import sys

from verify import Run, ROOT, HERE, digest, equal_records
from probe_original_query import audit_projection


class VendoredRun(Run):
    def __init__(self, relative):
        super().__init__("probe-vendored-assets")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", FIDELITY_VENDOR_RELATIVE_PATH=relative,
                        FIDELITY_EXTRA_ORIGINAL_INPUTS=json.dumps(["lib/vendored_assets.rb"]))
        self.evidence.update(stage="original registry279 VendoredAssets path-value prerequisite ONLY",
                             broader019_accepted=False, native_activation_accepted=False,
                             observation="raw root and path strings; no path/error normalization", transformations=[])

    def build(self, compiler):
        app = self.path / "input"
        source = HERE / "source/discourse/lib/vendored_assets.rb"
        target = app / "app/models/vendored_assets.rb"
        target.parent.mkdir(parents=True)
        shutil.copyfile(source, target)
        sha = digest(source.read_bytes())
        self.env["FIDELITY_VENDOR_SOURCE_SHA256"] = sha
        maps = [{"source": "lib/vendored_assets.rb", "generated": "app/models/vendored_assets.rb",
                 "source_sha256": sha, "generated_sha256": sha,
                 "selected_spans": [{"start_byte": 0, "end_byte": source.stat().st_size, "text_sha256": sha}],
                 "limitation": "complete original path helper ONLY; no registry/activation proof"}]
        (app / "projection-map.json").write_text(json.dumps(maps, indent=2) + "\n")
        for name, text in {"db/schema.rb": "ActiveRecord::Schema.define do\nend\n", "config/routes.rb": "Rails.application.routes.draw do\nend\n"}.items():
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.evidence["input_map"] = audit_projection(app)
        self.command("strict", [compiler, "--target", "spinel", app, "-o", self.path / "emitted"], timeout=120)
        shutil.copyfile(HERE / "test/vendored_assets_probe.rb", self.path / "probe.rb")
        (self.path / "entry.rb").write_text('require "json"\nrequire_relative "emitted/runtime/base64"\nrequire_relative "emitted/runtime/active_support_ext"\nrequire_relative "emitted/runtime/rails"\nrequire_relative "emitted/app/models"\nrequire_relative "probe"\n')
        self.command("native-compile", [ROOT / "spinel/bin/spinel", "--jobs=4", "--rbs", self.path / "emitted", self.path / "entry.rb", "-o", self.path / "probe"], timeout=120)
        assert (self.path / "probe").read_bytes()[:4] == bytes.fromhex("7f454c46")
        self.evidence["elf_sha256"] = digest((self.path / "probe").read_bytes())
        self.evidence["lowered_hashes"] = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
        self.save()

    def execute(self):
        # Every runtime uses the SAME actual application root/cwd and input;
        # neither a relative-path comparator nor a fake Rails root is allowed.
        self.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / "native.trace", self.path / "probe"], cwd=ROOT / "discourse", timeout=30)
        trace = (self.path / "native.trace").read_text()
        assert trace.count("execve(") == 1 and "connect(" not in trace
        self.evidence["native_no_child_or_network"] = True
        self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", self.path / "entry.rb"], cwd=ROOT / "discourse", timeout=30)
        equal_records(self.records("native"), self.records("compat"))
        original_input = self.env["FIDELITY_VENDOR_RELATIVE_PATH"]
        try:
            self.env["FIDELITY_VENDOR_RELATIVE_PATH"] = original_input + ".__owned_live_input__"
            self.command("native-live-input", [self.path / "probe"], cwd=ROOT / "discourse", timeout=30)
        finally:
            self.env["FIDELITY_VENDOR_RELATIVE_PATH"] = original_input
        before = self.records("native")[0]
        after = self.records("native-live-input")[0]
        assert before["root"] == after["root"] and before["path"] != after["path"], "native path was frozen at compile time"
        self.evidence["native_live_input_negative"] = "post-compile input changes original helper output, not merely the observation's input field"
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", HERE / "tools/vendored_assets_oracle_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        native = self.records("native")
        self.evidence["raw_path_comparison"] = {"native": native, "original_rails": oracle}
        self.save()
        equal_records(native, oracle)
        return {"scope": "original VendoredAssets raw root/path values ONLY", "native_equal": True, "compat_equal": True}

    def audit(self):
        audit_projection(self.path / "input")
        for name, sha in self.evidence.get("lowered_hashes", {}).items():
            assert digest((self.path / "emitted" / name).read_bytes()) == sha
        if "elf_sha256" in self.evidence:
            assert digest((self.path / "probe").read_bytes()) == self.evidence["elf_sha256"]
        self.provenance()
        sandbox = self.evidence.get("oracle_sandbox")
        if sandbox:
            assert sandbox["status"] == "stopped" and sandbox["cleanup"] == "child_exited"
            self.evidence["oracle_cleanup_verified"] = True
        self.evidence["post_execution_hashes_verified"] = True
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--relative-path", required=True, help="live input to the original path helper; never an oracle-produced input")
    parser.add_argument("--compiler", type=Path, default=ROOT / "roundhouse/target/release/roundhouse")
    args = parser.parse_args()
    import os
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = VendoredRun(args.relative_path)
    try:
        run.provenance()
        run.build(args.compiler.resolve())
        try:
            run.execute()
            run.oracle()
        finally:
            run.audit()
        run.evidence["status"] = "passed_original_vendored_path_prerequisite_ONLY"
        run.save()
        print(f"PASS path prerequisite ONLY; not registry/activation/019. Evidence: {run.path}")
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
