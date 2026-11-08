#!/usr/bin/env python3
"""Original plugin metadata construction ONLY; never native activation/019 proof."""
import argparse
import json
from pathlib import Path
import shutil
import sys

from verify import Run, ROOT, HERE, digest, equal_records
from probe_original_query import audit_projection


class MetadataRun(Run):
    def __init__(self):
        super().__init__("verify-plugin-metadata")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4",
                        FIDELITY_PLUGIN_SOURCE_ROOT=str(HERE / "source/discourse"),
                        FIDELITY_OFFICIAL_PLUGIN_RESOURCE=str(HERE / "source/discourse/config/official_plugins.json"))
        self.evidence.update(stage="original complete metadata class + whole parse_from_source construction prefix ONLY",
                             broader019_accepted=False, native_activation_accepted=False, transformations=[])

    def build(self, compiler):
        app = self.path / "input"
        self.command("project", ["ruby", HERE / "tools/project_plugin_activation.rb", HERE / "source/discourse", app, "--metadata-prefix"])
        for name, text in {"db/schema.rb": "ActiveRecord::Schema.define do\nend\n", "config/routes.rb": "Rails.application.routes.draw do\nend\n"}.items():
            target = app / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.evidence["input_map"] = audit_projection(app)
        out = self.path / "emitted"
        self.command("strict", [compiler, "--target", "spinel", app, "-o", out], timeout=120)
        source = (HERE / "source/discourse/lib/plugin/metadata.rb").read_bytes()
        call = b'JSON.load_file(Rails.root.join("config/official_plugins.json").to_s)'
        assert source.count(call) == 1
        start = source.index(call)
        lowered = (out / "app/models/plugin/metadata.rb").read_text()
        assert 'JSON.parse(::File.read(Rails.root.join("config/official_plugins.json").to_s, encoding: "UTF-8"))' in lowered
        self.evidence["transformations"] = [{
            "feature": "one-argument stdlib JSON.load_file UTF-8 file composition",
            "source": "lib/plugin/metadata.rb", "start_byte": start, "end_byte": start + len(call),
            "line": source[:start].count(b"\n") + 1, "text_sha256": digest(call),
            "reason": "actual original metadata initializer refused native JSON.load_file",
            "lowering": 'JSON.parse(::File.read(path, encoding: "UTF-8")); no input data cached/generated',
            "equivalence": "pending original/native/same-lowered/realRails metadata prefix comparisons",
        }]
        # Generic project assembly does not copy arbitrary config resources.
        # Copy the complete original file, never a parsed/frozen Array/Set.
        shutil.copyfile(app / "config/official_plugins.json", out / "config/official_plugins.json")
        probe = (HERE / "test/plugin_metadata_probe.rb").read_text()
        (self.path / "probe.rb").write_text(probe)
        entry = '\n'.join(['require_relative "emitted/runtime/base64"',
                           'require_relative "emitted/runtime/json_impl"',
                           'require_relative "emitted/runtime/active_support_ext"',
                           'require_relative "emitted/runtime/rails"',
                           'require_relative "emitted/app/models"',
                           'require_relative "probe"', ''])
        (self.path / "entry.rb").write_text(entry)
        self.command("native-compile", [ROOT / "spinel/bin/spinel", "--jobs=4", "--rbs", out, self.path / "entry.rb", "-o", self.path / "probe"], timeout=120)
        binary = self.path / "probe"
        assert binary.read_bytes()[:4] == bytes.fromhex("7f454c46")
        self.evidence["elf_sha256"] = digest(binary.read_bytes())
        self.evidence["same_lowered_hashes"] = {str(path.relative_to(out)): digest(path.read_bytes()) for path in out.rglob("*.rb")}
        self.save()

    def execute(self):
        out = self.path / "emitted"
        self.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / "native.trace", self.path / "probe"], cwd=out, timeout=30)
        trace = (self.path / "native.trace").read_text()
        assert trace.count("execve(") == 1 and "connect(" not in trace
        self.evidence["native_no_child_or_network"] = True
        self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", self.path / "entry.rb"], cwd=out, timeout=30)
        original = '\n'.join(['require "set"', 'require "json"', 'require "active_support/core_ext/string/filters"',
                              'require_relative "runtime/rails"',
                              f'require {json.dumps(str(HERE / "source/discourse/lib/plugin/metadata.rb"))}',
                              f'require {json.dumps(str(self.path / "input/app/models/plugin/instance.rb"))}',
                              f'load {json.dumps(str(self.path / "probe.rb"))}', ''])
        self.command("original-prefix", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", "-e", original], cwd=out, timeout=30)
        equal_records(self.records("native"), self.records("compat"))
        equal_records(self.records("native"), self.records("original-prefix"))
        assert len(self.records("native")) == 3
        # After compilation, change ONLY an owned TEST metadata-input copy.
        # A parser reading live text must observe it; a saved answer cannot.
        fixture = self.path / "derived-metadata-input"
        for name in ("discourse-assign", "discourse-events", "discourse-solved"):
            source = HERE / "source/discourse/plugins" / name / "plugin.rb"
            target = fixture / "plugins" / name / "plugin.rb"
            target.parent.mkdir(parents=True, exist_ok=True)
            data = source.read_bytes()
            if name == "discourse-assign":
                old = b"# name: discourse-assign"
                assert data.count(old) == 1
                data = data.replace(old, b"# name: fidelity-derived-metadata-negative")
            target.write_bytes(data)
        before = self.env["FIDELITY_PLUGIN_SOURCE_ROOT"]
        try:
            self.env["FIDELITY_PLUGIN_SOURCE_ROOT"] = str(fixture)
            self.command("native-derived-metadata", [self.path / "probe"], cwd=out, timeout=30)
        finally:
            self.env["FIDELITY_PLUGIN_SOURCE_ROOT"] = before
        changed = self.records("native-derived-metadata")
        assert changed[0]["name"] == "fidelity-derived-metadata-negative"
        try:
            equal_records(changed, self.records("native"))
        except AssertionError:
            self.evidence["live_metadata_input_negative_control"] = "detected native post-compile owned TEST source-data change; original inputs unchanged"
        else:
            raise AssertionError("native metadata parser did not read live input")
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", HERE / "tools/plugin_metadata_oracle_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        for name in ("native", "compat", "original-prefix"):
            equal_records(self.records(name), oracle)
        return {"native_equal": True, "compat_equal": True, "original_prefix_equal": True,
                "scope": "actual original metadata parsing/construction ONLY; no native script activation, settings, query or page"}

    def oracle_equivalence(self):
        return "native/same-lowered/original-prefix match real Rails metadata construction; live post-compile TEST input change detected; NOT activation/query/page"

    def audit(self):
        audit_projection(self.path / "input")
        out = self.path / "emitted"
        assert (out / "config/official_plugins.json").read_bytes() == (HERE / "source/discourse/config/official_plugins.json").read_bytes()
        for name, sha in self.evidence.get("same_lowered_hashes", {}).items():
            assert digest((out / name).read_bytes()) == sha
        sandbox = self.evidence.get("oracle_sandbox")
        if sandbox:
            assert sandbox["status"] == "stopped" and sandbox["cleanup"] == "child_exited"
            self.evidence["oracle_cleanup_verified"] = True
        self.provenance()
        self.evidence["post_execution_hashes_verified"] = True
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "roundhouse/target/release/roundhouse")
    args = parser.parse_args()
    import os
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = MetadataRun()
    try:
        run.provenance()
        run.build(args.compiler.resolve())
        try:
            run.execute()
            run.env["FIDELITY_EXTRA_ORIGINAL_INPUTS"] = json.dumps(["lib/plugin/metadata.rb", "lib/plugin/instance.rb"])
            run.oracle()
        finally:
            run.audit()
        run.evidence["status"] = "passed_original_plugin_metadata_prefix_ONLY"
        run.save()
        print(f"PASS original metadata construction ONLY; native activation/019 NOT ACCEPTED. Evidence: {run.path}")
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
