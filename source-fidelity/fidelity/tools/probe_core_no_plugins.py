#!/usr/bin/env python3
"""Separate core-no-plugins reference/input experiment, never the full/plugin gate.

LOAD_PLUGINS=0 is the pinned application's original boot switch, not disabled
plugin settings. The guarded Rails reference runs FIRST; existing 019/plugin
acceptance remains untouched and no failed/survey compiler output is executed.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys

from verify import Run, ROOT, HERE, digest
from probe_original_query import QueryRun, audit_projection


class CoreNoPluginsRun(QueryRun):
    def __init__(self):
        Run.__init__(self, "probe-core-no-plugins")
        self.trace_activation = False
        self.reference_only = True
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", CARGO_INCREMENTAL="0",
                        LOAD_PLUGINS="0", FIDELITY_QUERY_MATRIX="1",
                        FIDELITY_EXTRA_ORIGINAL_INPUTS=json.dumps(["lib/topic_query.rb", "lib/guardian.rb"]))
        self.evidence.update(stage="original core /latest NO PLUGINS milestone; query/reference experiment ONLY",
                             full_plugin019_accepted=False, core_page_accepted=False,
                             profile={"LOAD_PLUGINS": "0", "official_plugins_excluded": True}, transformations=[])

    def oracle(self):
        if not self.reference_only and "actual_core_constructor_reference" in self.evidence:
            # Compare with the independently run FIRST reference, never use its
            # data as native runtime input. Avoid reusing stopped fixture env or
            # appending a second set of unit-control rejection logs to one run.
            self.evidence["rails_parity"] = self.compare_oracle(self.evidence["actual_core_constructor_reference"])
            self.evidence["constructor_reference_reused_for_comparison_only"] = True
            self.save()
            return
        super().oracle()

    def oracle_arguments(self):
        wrapper = "core_provider_oracle.rb" if getattr(self, "provider_dependencies", False) else "core_no_plugins_oracle.rb"
        return [HERE / "tools" / wrapper,
                HERE / "tools/core_no_plugins_reference_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        text = (self.path / "rails-oracle.stdout").read_text()
        def single(prefix):
            values = [json.loads(line.removeprefix(prefix)) for line in text.splitlines() if line.startswith(prefix)]
            assert len(values) == 1, prefix
            return values[0]
        profile = single("FIDELITY_CORE_NO_PLUGINS ")
        assert profile["load_plugins_env"] == "0" and profile["load_plugins"] is False
        assert not profile["plugin_instance_names"] and not profile["loaded_plugin_sources"] and not profile["compiled_plugin_sources"]
        for path, sha in profile["original_configuration"].items():
            assert self.evidence["source_hashes"][path] == sha
        self.evidence["actual_no_plugin_boot"] = profile
        self.evidence["original_core_query_reference"] = single("FIDELITY_CORE_REFERENCE ")
        self.evidence["actual_core_constructor_reference"] = oracle
        if getattr(self, "provider_dependencies", False):
            trace = single("FIDELITY_CORE_PROVIDER_TRACE ")
            assert trace["successful_oracle"]
            events = trace["events"]
            assert [event["order"] for event in events] == list(range(1, len(events) + 1))
            assert any(event["method"] == "all" and event["event"] == "call" and event["source"][0].endswith("/lib/site_settings/db_provider.rb") for event in events)
            assert any(event["method"] == "new_row_materializer" and event["event"] == "call" and event["source"][0].endswith("/mini_sql/postgres/deserializer_cache.rb") for event in events)
            assert any(event.get("anonymous_row_class") and event.get("observed_row_fields") == ["name", "data_type", "value"] for event in events)
            assert any(event["method"] == "type_map=" and event["event"] == "c_call" for event in events)
            assert any(event["method"] == "getvalue" and event["event"] == "c_return" and event.get("result_class") == "Integer" for event in events)
            assert any(event["method"] == "getvalue" and event["event"] == "c_return" and event.get("result_class") == "String" for event in events)
            expected = {}
            for group in self.evidence["framework_sources"]:
                for item in group["files"]:
                    path = ROOT / "run/bundle/ruby/4.0.0/gems" / f'{group["gem"]}-{group["version"]}' / item["package_member"]
                    expected[str(path)] = item["sha256"]
            assert trace["loaded_provider_source_hashes"]
            for path, sha in trace["loaded_provider_source_hashes"].items():
                assert expected.get(path) == sha, "actual loaded provider bytes differ from verified package"
            self.evidence["original_core_provider_trace"] = trace
        if self.env.get("FIDELITY_CORE_HTTP_REFERENCE") == "1":
            self.evidence["original_core_http_reference"] = single("FIDELITY_CORE_HTTP_REFERENCE ")
        if self.reference_only:
            return {"reference_only": True, "native_equal": False, "core_page_accepted": False}
        result = super().compare_oracle(oracle)
        result["scope"] = "core-no-plugins original constructor prefix ONLY; full query/native boot/page UNPROVED"
        return result

    def registry_api(self, compiler):
        # No plugin campaign/synthetic registration proof for this milestone.
        self.evidence["registry_api_status"] = "not launched: no-plugin core priority"

    def initial_reference(self):
        shutil.copyfile(HERE / "test/query_initializer_probe.rb", self.path / "probe.rb")
        try:
            self.oracle()
        finally:
            sandbox = self.evidence.get("oracle_sandbox")
            if sandbox:
                assert sandbox["status"] == "stopped" and sandbox["cleanup"] == "child_exited"
                self.evidence["oracle_cleanup_verified"] = True
                self.save()

    def measure_core_getter(self, compiler):
        import core_getter_input
        app = self.path / "core-getter-input"
        self.evidence["core_getter_inputs"] = core_getter_input.materialize(app)
        if getattr(self, "provider_dependencies", False):
            import core_provider_input
            self.evidence["core_provider_dependency_inputs"] = core_provider_input.materialize(app)
        (app / "db").mkdir(exist_ok=True)
        (app / "db/schema.rb").write_text(core_getter_input.schema(self))
        (app / "config/routes.rb").write_text("Rails.application.routes.draw do\nend\n")
        code, _ = self.command("core-getter-strict-emit", [compiler, "--target", "spinel", app, "-o", self.path / "core-getter-emitted"], check=False, timeout=120)
        from probe_original_query import diagnostics
        stderr = (self.path / "core-getter-strict-emit.stderr").read_text()
        self.evidence["core_getter_inventory"] = {"strict_returncode": code, "diagnostics": diagnostics(stderr, app),
            "raw_stderr": "core-getter-strict-emit.stderr", "output_executed": False,
            "warning": "compile-only complete source candidate, NOT native getter/boot/query/page proof"}
        self.save()

    def measure_full(self, compiler):
        super().measure_full(compiler)
        assert all(not item["source"].startswith("plugins/") for item in self.evidence["full_query_inputs"])
        self.evidence["core_native_input_profile"] = {
            "LOAD_PLUGINS": self.env["LOAD_PLUGINS"],
            "plugin_source_projections": [],
            "scope": "complete original TopicQuery/TopicList; supporting core projections, NOT native full boot",
            "source_sha256": {item["source"]: item["source_sha256"] for item in self.evidence["full_query_inputs"]},
        }
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "roundhouse/target/release/roundhouse")
    parser.add_argument("--reference-only", action="store_true")
    parser.add_argument("--getter-input", action="store_true", help="also measure complete original FIRST core setting declaration/provider/boot candidate; never executes failed output")
    parser.add_argument("--provider-dependencies", action="store_true", help="with --getter-input, include original DB initializer/facade and verified MiniSql/multisite source gems; compile-only")
    parser.add_argument("--http-reference", action="store_true", help="also invoke original Rack/controller JSON and document GETs, without a server or plugin boot")
    args = parser.parse_args()
    if args.provider_dependencies and (not args.getter_input or args.reference_only):
        parser.error("--provider-dependencies requires --getter-input and is compile-only")
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = CoreNoPluginsRun()
    run.provider_dependencies = args.provider_dependencies
    if args.http_reference:
        run.env.update(FIDELITY_CORE_HTTP_REFERENCE="1", FIDELITY_CORE_REFERENCE_DIRECTORY=str(run.path))
    try:
        run.provenance()
        compiler = args.compiler.resolve()
        run.evidence["roundhouse_compiler"] = {"path": str(compiler), "sha256": digest(compiler.read_bytes())}
        _, status = run.command("roundhouse-source-status", ["git", "-C", ROOT / "roundhouse", "status", "--porcelain"])
        _, difference = run.command("roundhouse-source-diff", ["git", "-C", ROOT / "roundhouse", "diff", "HEAD"])
        run.evidence["roundhouse_source_snapshot"] = {"status": status, "diff_sha256": digest(difference.encode())}
        run.initial_reference()
        if not args.reference_only:
            run.measure_full(args.compiler.resolve())
            if args.getter_input:
                run.measure_core_getter(args.compiler.resolve())
            run.reference_only = False
            run.env["FIDELITY_QUERY_MATRIX"] = "0"
            run.initializer(args.compiler.resolve())
        run.provenance()
        run.evidence["status"] = "measured_core_no_plugins; full_native_query_page_NOT_accepted"
        run.save()
        print(f"CORE REFERENCE/INPUT ONLY, not page acceptance. Evidence: {run.path}")
        return 0 if args.reference_only else 1
    except Exception as error:
        import traceback
        traceback.print_exc()
        run.evidence.update(status="failed_core_no_plugins_experiment", error=repr(error))
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
