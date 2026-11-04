#!/usr/bin/env python3
"""Positive ANONYMOUS security-slice milestone; never ticket019 or /latest acceptance."""
import json
import os
from pathlib import Path
import shutil
import sys

from verify import Run, HERE, ROOT, digest, equal_records
from verify_topic_query import TopicQueryRun, ENTRY

SCOPE = "original anonymous category-security projection ONLY; NOT full default_results/list_latest, authenticated/admin, settings boot, serializers/controller/document or /latest"


class AnonymousSecurityRun(TopicQueryRun):
    def __init__(self):
        Run.__init__(self, "verify-anonymous-security")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", CARGO_INCREMENTAL="0")
        self.evidence["stage"] = SCOPE
        self.evidence["broader019_accepted"] = False

    def emit_options(self):
        return ["--construction-context-root", self.path / "entry.rb",
                "--construction-context-root", self.path / "probe.rb"]

    def generate(self):
        (self.path / "entry.rb").write_text(ENTRY)
        shutil.copyfile(HERE / "test/topic_query_probe.rb", self.path / "probe.rb")
        super().generate()
        # The broad gate additionally executes member/admin and a forced cold
        # getter; do not pretend their lazy-loaded files ran in this slice.
        self.env["FIDELITY_EXTRA_ORIGINAL_INPUTS"] = json.dumps([
            "lib/topic_query.rb", "lib/guardian.rb", "lib/guardian/topic_guardian.rb",
            "lib/guardian/category_guardian.rb", "app/models/site_setting.rb",
            "lib/site_setting_extension.rb"])
        report = json.loads((self.path / "emitted/construction-contexts.json").read_text())
        assert not report["refusals"]
        assert [c["class"] for c in report["contexts"]] == ["Guardian"]
        assert len(report["rewrites"]) == 1
        rewrite = report["rewrites"][0]
        assert (rewrite["owner"], rewrite["method"], rewrite["result"]) == ("TopicGuardian", "filter_allowed_categories", "Bool(false)")
        def location(span):
            assert span["file"] > 0, "synthetic specialization witness"
            path = Path(report["source_catalogue"][span["file"] - 1])
            data = path.read_bytes()
            return {"source": str(path.relative_to(self.path / "input")),
                    "line": data[:span["start"]].count(b"\n") + 1,
                    "text_sha256": digest(data[span["start"]:span["end"]])}
        locations = [location(rewrite["expression"]), location(rewrite["retained_left"])]
        locations += [location(s) for s in rewrite["witnesses"]]
        locations += [location(c["constructor"]) for c in report["contexts"]]
        assert [(x["source"], x["line"]) for x in locations] == [
            ("app/models/topic_guardian.rb", 273), ("app/models/topic_guardian.rb", 273),
            ("app/models/guardian.rb", 140), ("app/models/guardian.rb", 44),
            ("app/models/guardian.rb", 122)]
        self.evidence["construction_context"] = {"ledger": report, "resolved_source_witnesses": locations,
            "roots": {p: digest((self.path / p).read_bytes()) for p in ("entry.rb", "probe.rb")}}
        self.evidence["transformations"].append({
            "feature": "generic guarded nil-construction context specialization in shared IR",
            "source": locations, "generated": "emitted/construction-contexts.json",
            "reason": "source-derived falsy anonymous admin predicate; original left call retained exactly once",
            "guard": "unexpected nonnil constructor input or truthy predicate raises before removed setting dependency",
            "equivalence": "awaiting native/same-lowered/full-Rails selected-slice comparison"})
        self.save()

    def validate_guardian(self, guardian):
        assert "SiteSetting.suppress_secured_categories_from_admin" not in guardian
        assert "is_admin? && (raise " in guardian and "requires a falsy predicate" in guardian, "missing runtime fact guard"

    def measure_settings_closure(self, app):
        self.evidence["settings_closure_experiment"] = {
            "launched": False, "reason": "not reachable in this anonymous slice; full settings remains unaccepted"}

    def audit_additional_inputs(self):
        assert self.evidence["settings_closure_experiment"]["launched"] is False

    def provenance(self):
        super().provenance()
        context = self.evidence.get("construction_context")
        if context:
            for path, sha in context["roots"].items():
                assert digest((self.path / path).read_bytes()) == sha
            assert json.loads((self.path / "emitted/construction-contexts.json").read_text()) == context["ledger"]

    def run_partial(self):
        pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
        assert (pg_dir / "pg.rb").is_file(), "set SPINEL_PG_DIR to the existing spinel-pg checkout"
        self.evidence["pg_driver_sha256"] = {str(p.relative_to(pg_dir)): digest(p.read_bytes()) for p in sorted(pg_dir.rglob("*.rb"))}
        self.command("native-compile", [ROOT / "spinel/spinel", "--jobs=4", "--rbs", self.path / "emitted",
                                      "-I", pg_dir, self.path / "entry.rb", "-o", self.path / "probe"])
        assert (self.path / "probe").read_bytes()[:4] == b"\x7fELF"
        self.evidence["native_elf_sha256"] = digest((self.path / "probe").read_bytes())
        self.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / "native.trace", self.path / "probe"], timeout=60)
        trace = (self.path / "native.trace").read_text()
        assert trace.count("execve(") == 1, "native spawned another process"
        connections = [line for line in trace.splitlines() if "connect(" in line]
        assert len(connections) >= 2
        assert all('htons(5499)' in line and 'inet_addr("127.0.0.1")' in line for line in connections), "unexpected native network endpoint"
        self.evidence["native_execution_path"] = {"execve_count": 1, "pg_connections": len(connections),
            "trace": "native.trace", "ruby_child": False, "cache_service_effects_in_selected_slice": False}
        compat = self.path / "compat"
        shutil.copytree(self.path / "emitted", compat / "emitted")
        for name in ("entry.rb", "probe.rb"):
            shutil.copyfile(self.path / name, compat / name)
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        native_hashes = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
        compat_hashes = {str(p.relative_to(compat / "emitted")): digest(p.read_bytes()) for p in (compat / "emitted").rglob("*.rb")}
        differences = [p for p in native_hashes if native_hashes[p] != compat_hashes[p]]
        assert differences == ["runtime/pg_driver.rb"]
        self.evidence["same_lowered_ruby"] = {"hashes": native_hashes, "platform_only_difference": differences,
            "entry_sha256": digest((self.path / "entry.rb").read_bytes()), "probe_sha256": digest((self.path / "probe.rb").read_bytes())}
        self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
        self.env["FIDELITY_NEGATIVE_SCOPE"] = "1"
        try:
            self.command("native-wrong-scope", [self.path / "probe"], timeout=60)
            self.command("compat-wrong-scope", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
        finally:
            del self.env["FIDELITY_NEGATIVE_SCOPE"]
        native = self.records("native")
        equal_records(native, self.records("compat"))
        equal_records(self.records("native-wrong-scope"), self.records("compat-wrong-scope"))
        assert any(r.get("kind") == "row" for r in native)
        rows = [r for r in native if r.get("kind") == "fixture"]
        assert [r["id"] for r in rows] == self.evidence["source_fixture"]["expected_ids"]
        assert [r["id"] for r in self.records("native-wrong-scope") if r.get("kind") == "fixture"] == self.evidence["source_fixture"]["wrong_scope_expected_ids"]
        assert next(r for r in rows if r["id"] == 107)["visible"] is None
        assert next(r for r in rows if r["id"] == 108)["category_id"] is None
        assert next(r for r in rows if r["id"] == 109)["category_name"] is None
        wrong = json.loads(json.dumps(native))
        next(r for r in wrong if r.get("kind") == "row")["visible"] = 1
        try:
            equal_records(native, wrong)
        except AssertionError:
            self.evidence["type_negative_control"] = True
        else:
            raise AssertionError("boolean/integer comparator control did not fail")
        self.evidence["query_observations"] = {name: [json.loads(line.removeprefix("FIDELITY_QUERY ")) for line in (self.path / f"{name}.stdout").read_text().splitlines() if line.startswith("FIDELITY_QUERY ")] for name in ("native", "compat")}
        assert self.evidence["query_observations"]["native"] == self.evidence["query_observations"]["compat"]
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", HERE / "tools/anonymous_security_oracle_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        equal_records(self.records("native"), oracle)
        equal_records(self.records("compat"), oracle)
        try:
            equal_records(self.records("native-wrong-scope"), oracle)
        except AssertionError:
            self.evidence["scope_negative_control"] = "native omission of actual category filter rejected against full Rails oracle; restricted case111 leaks only in wrong consumer"
        else:
            raise AssertionError("native category negative control was not rejected")
        observations = [json.loads(line.removeprefix("FIDELITY_ANONYMOUS_REACHABILITY ")) for line in (self.path / "rails-oracle.stdout").read_text().splitlines() if line.startswith("FIDELITY_ANONYMOUS_REACHABILITY ")]
        assert len(observations) == 1
        observation = observations[0]
        assert observation["setting_getter_calls"] == 0 and observation["successful_probe"]
        assert observation["counts"]["filter_allowed_categories"] > 0
        assert observation["counts"]["is_admin?"] > 0
        self.evidence["actual_anonymous_request_reachability"] = observation
        return {"native_equal": True, "compat_equal": True, "scope": SCOPE,
                "live_rows": sum(r.get("kind") == "row" for r in oracle),
                "fixture_rows": sum(r.get("kind") == "fixture" for r in oracle),
                "hydration": "native/compat batched preload vs Rails joined hydration; query counts NOT claimed equivalent"}

    def oracle_equivalence(self):
        return "native and same-lowered CRuby match actual full Rails selected anonymous security-slice values/types/NULLs and controls; NOT full boot, query, effects or page equivalence"


def main():
    # Bound all compiler/oracle descendants, even when invoked without taskset.
    available = sorted(os.sched_getaffinity(0))
    os.sched_setaffinity(0, available[:4])
    run = AnonymousSecurityRun()
    try:
        run.provenance()
        run.generate()
        run.run_partial()
        run.oracle()
        run.provenance()
        assert run.evidence["oracle_cleanup_verified"]
        assert run.evidence["rails_parity"]["native_equal"] and run.evidence["rails_parity"]["compat_equal"]
        assert run.evidence["scope_negative_control"] and run.evidence["type_negative_control"]
        run.evidence["status"] = "passed_labelled_anonymous_security_slice_only"
        run.save()
        print(f"PASS labelled anonymous category-security slice ONLY; broader019 and /latest NOT ACCEPTED. Evidence: {run.path}")
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
