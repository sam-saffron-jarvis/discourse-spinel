#!/usr/bin/env python3
"""Fail-closed original full-query measurement and separately labelled prefix proof.

Never execute survey/error output. Complete original TopicQuery/TopicList bodies
are measured first; the executable initializer projection copies whole methods,
not a hand-written query. Neither mode accepts ticket019, native boot or /latest.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import sys

from verify import Run, ROOT, HERE, digest, equal_records
from verify_topic_query import ENTRY

COMPLETE = (
    ("lib/topic_query.rb", "app/models/topic_query.rb"),
    ("app/models/topic_list.rb", "app/models/topic_list.rb"),
    ("lib/topic_query/private_message_lists.rb", "app/models/topic_query/private_message_lists.rb"),
)


def audit_projection(app):
    maps = json.loads((app / "projection-map.json").read_text())
    for item in maps:
        original = (HERE / "source/discourse" / item["source"]).read_bytes()
        generated = (app / item["generated"]).read_bytes()
        assert digest(original) == item["source_sha256"]
        assert digest(generated) == item["generated_sha256"]
        assert len(original) == len(generated)
        selected = bytearray(len(original))
        for span in item["selected_spans"]:
            start, end = span["start_byte"], span["end_byte"]
            assert generated[start:end] == original[start:end]
            assert digest(original[start:end]) == span["text_sha256"]
            selected[start:end] = b"1" * (end - start)
        assert all(selected[i] or byte in (10, 32) for i, byte in enumerate(generated))
    return maps


def diagnostics(stderr, app):
    """Compiler order, not an invented runtime-reachability ranking."""
    results = []
    for line in stderr.splitlines():
        if "error[" not in line:
            continue
        item = {"diagnostic": line, "source_span": None}
        match = re.search(r"([^\s]+\.rb):(\d+):(\d+): error\[", line)
        if match:
            path = Path(match[1])
            if path.is_file() and path.is_relative_to(app):
                data = path.read_bytes()
                lineno, column = int(match[2]), int(match[3])
                rows = data.splitlines(keepends=True)
                if 0 < lineno <= len(rows):
                    start = sum(map(len, rows[:lineno - 1])) + len(rows[lineno - 1].decode()[:column - 1].encode())
                    item["source_span"] = {"file": str(path.relative_to(app)), "line": lineno,
                        "column": column, "start_byte": start, "file_sha256": digest(data)}
        results.append(item)
    return results


class QueryRun(Run):
    def __init__(self):
        super().__init__("probe-original-query")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", CARGO_INCREMENTAL="0", FIDELITY_QUERY_MATRIX="0")
        self.evidence.update(stage="original complete query/list dependency measurement; initializer prefix is NOT full-query/settings/plugin/page proof", broader019_accepted=False)

    def full_input(self):
        app = self.path / "full-input"
        self.command("project-support", ["ruby", HERE / "tools/project_topic_query.rb", HERE / "source/discourse", app])
        (app / "db").mkdir(exist_ok=True)
        (app / "db/schema.rb").write_text(self.schema())
        (app / "config").mkdir(exist_ok=True)
        (app / "config/routes.rb").write_text("Rails.application.routes.draw do\nend\n")
        maps = json.loads((app / "projection-map.json").read_text())
        for original, target in COMPLETE:
            data = (HERE / "source/discourse" / original).read_bytes()
            destination = app / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            maps = [m for m in maps if m["generated"] != target]
            maps.append({"source": original, "generated": target, "source_sha256": digest(data),
                "generated_sha256": digest(data), "selected_spans": [{"start_byte": 0, "end_byte": len(data), "text_sha256": digest(data)}],
                "limitation": "COMPLETE original file; supporting Guardian/models are audited projections; no native plugin/settings boot"})
        (app / "projection-map.json").write_text(json.dumps(maps, indent=2) + "\n")
        self.evidence["full_query_inputs"] = audit_projection(app)
        (self.path / "full-entry.rb").write_text(ENTRY.replace('require_relative "probe"', 'query = TopicQuery.new(nil, page: ENV.fetch("FIDELITY_QUERY_PAGE", "0").to_i, per_page: 20)\nlist = query.list_latest\nraise "missing original TopicList" unless list.is_a?(TopicList)\n'))
        return app

    def measure_full(self, compiler):
        app = self.full_input()
        code, _ = self.command("full-strict-emit", [compiler, "--target", "spinel", app, "-o", self.path / "full-emitted"], check=False, timeout=120)
        errors = diagnostics((self.path / "full-strict-emit.stderr").read_text(), app)
        self.evidence["full_query_inventory"] = {"strict_lower_returncode": code, "errors": errors,
            "first_reported_lower_error": errors[0] if errors else None,
            "warning": "compiler diagnostic order is NOT first runtime reachability",
            "compat": "NOT EXECUTED: full source closure has not passed strict admission",
            "native": "NOT COMPILED/EXECUTED: full source closure has not passed strict admission",
            "status": "blocked_before_full_query_execution"}
        self.save()

    def initializer(self, compiler):
        app = self.path / "prefix-input"
        self.command("project-initializer", ["ruby", HERE / "tools/project_query_initializer.rb", HERE / "source/discourse", app])
        for name, text in {"db/schema.rb": "ActiveRecord::Schema.define do\nend\n", "config/routes.rb": "Rails.application.routes.draw do\nend\n"}.items():
            target = app / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.evidence["initializer_inputs"] = audit_projection(app)
        self.command("prefix-strict-emit", [compiler, "--target", "spinel", app, "-o", self.path / "emitted"])
        entry = '\n'.join([
            'require_relative "emitted/runtime/active_support_ext"',
            'require_relative "emitted/runtime/json_builder"',
            'require_relative "emitted/app/models"',
            'module FidelityDriver; def self.encode(value); JsonBuilder.encode_value(value); end; end',
            'require_relative "probe"', '',
        ])
        (self.path / "entry.rb").write_text(entry)
        shutil.copyfile(HERE / "test/query_initializer_probe.rb", self.path / "probe.rb")
        self.command("prefix-native-compile", [ROOT / "spinel/bin/spinel", "--jobs=4", "--rbs", self.path / "emitted", "-I", Path.home() / ".cache/spin/packages/pg-0.2.0", self.path / "entry.rb", "-o", self.path / "prefix-probe"])
        assert (self.path / "prefix-probe").read_bytes()[:4] == b"\x7fELF"
        self.evidence["prefix_elf_sha256"] = digest((self.path / "prefix-probe").read_bytes())
        compat = self.path / "compat"
        shutil.copytree(self.path / "emitted", compat / "emitted")
        for name in ("entry.rb", "probe.rb"):
            shutil.copyfile(self.path / name, compat / name)
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        hashes = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
        changes = [name for name, sha in hashes.items() if digest((compat / "emitted" / name).read_bytes()) != sha]
        assert changes == ["runtime/pg_driver.rb"]
        self.evidence["same_lowered_prefix"] = {"hashes": hashes, "platform_only_difference": changes}
        for name, page, bad in (("page0", "0", "0"), ("page1", "1", "0"), ("invalid", "0", "1")):
            self.env.update(FIDELITY_QUERY_PAGE=page, FIDELITY_QUERY_BAD_OPTION=bad)
            self.command(f"native-{name}", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / f"native-{name}.trace", self.path / "prefix-probe"], timeout=60)
            trace = (self.path / f"native-{name}.trace").read_text()
            assert trace.count("execve(") == 1 and "connect(" not in trace
            self.command(f"compat-{name}", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
            equal_records(self.records(f"native-{name}"), self.records(f"compat-{name}"))
        assert self.records("native-page0")[0]["input_page"] == 0
        assert self.records("native-page1")[0]["input_page"] == 1
        assert self.records("native-invalid")[0]["kind"] == "invalid_option"
        self.evidence["prefix_status"] = "native_same_lowered_initializer_values_and_errors_only; not plugin/settings boot or list_latest"
        self.evidence["transformations"] = []
        self.env["FIDELITY_EXTRA_ORIGINAL_INPUTS"] = json.dumps(["lib/topic_query.rb", "lib/guardian.rb"])
        self.env.update(FIDELITY_QUERY_PAGE="0", FIDELITY_QUERY_BAD_OPTION="0")
        self.env["FIDELITY_QUERY_MATRIX"] = "1"
        try:
            self.oracle()
        finally:
            # Run.oracle records/reaps the owned fixture even when parity
            # raises. Require that failure-path lifecycle evidence too.
            sandbox = self.evidence.get("oracle_sandbox")
            if sandbox:
                assert sandbox["status"] == "stopped" and sandbox["cleanup"] == "child_exited", "oracle fixture cleanup unproved"
                self.evidence["oracle_cleanup_verified"] = True
                self.save()
        audit_projection(app)
        for name, sha in hashes.items():
            assert digest((self.path / "emitted" / name).read_bytes()) == sha
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", HERE / "tools/query_initializer_oracle_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        native = sum((self.records("native-" + case) for case in ("page0", "page1", "invalid")), [])
        compat = sum((self.records("compat-" + case) for case in ("page0", "page1", "invalid")), [])
        registrations = [json.loads(line.removeprefix("FIDELITY_QUERY_REGISTRATIONS "))
            for line in (self.path / "rails-oracle.stdout").read_text().splitlines()
            if line.startswith("FIDELITY_QUERY_REGISTRATIONS ")]
        assert len(registrations) == 1
        self.evidence["actual_rails_query_registration_inventory"] = registrations[0]
        mismatches = [{"index": i, "native": left, "actual_rails": right}
            for i, (left, right) in enumerate(zip(native, oracle)) if left != right]
        if len(native) != len(oracle):
            mismatches.append({"native_count": len(native), "oracle_count": len(oracle)})
        if mismatches:
            self.evidence["initializer_parity_mismatches"] = mismatches
            self.evidence["initializer_parity_scope"] = "FAIL: preserve live plugin boot state/error text; never trim mismatch or seed observed names"
            self.save()
        equal_records(native, oracle)
        equal_records(compat, oracle)
        return {"native_equal": True, "compat_equal": True, "scope": "whole initializer prefix, page0/page1 copy/identity and invalid-option error ONLY; full query and native plugin/bootstrap state remain unproved"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--initializer", action="store_true", help="also execute the separately labelled whole-method initializer prefix; never accept full query")
    parser.add_argument("--compiler", type=Path, default=ROOT / "roundhouse/target/release/roundhouse")
    args = parser.parse_args()
    import os
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = QueryRun()
    try:
        run.provenance()
        run.measure_full(args.compiler.resolve())
        if args.initializer:
            run.initializer(args.compiler.resolve())
        run.provenance()
        run.evidence["status"] = "blocked_full_original_query; initializer_is_only_a_dependency_prefix"
        run.save()
        print(f"NOT ACCEPTED: original full query remains unproved. Evidence: {run.path}")
        return 1
    except Exception as error:
        import traceback
        traceback.print_exc()
        run.evidence.update(status="failed", error=repr(error))
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
