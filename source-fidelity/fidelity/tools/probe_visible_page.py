#!/usr/bin/env python3
"""Stage1: RUN a source-derived partial default_results visible/paged relation.

Cumulative with Stage0; not complete default_results, full query or page success.
Any strict compile, native exit, materialization, trace or parity failure exits 1.
"""
import json
import os
from pathlib import Path
import shutil

from probe_portable_security import PortableSecurityRun, boot_record
from verify import ROOT, HERE, digest, equal_records

COMPONENT = HERE / "progressive/stage1"


class VisiblePageRun(PortableSecurityRun):
    def __init__(self):
        super().__init__()
        self.evidence.update(stage=__doc__, profile="progressive Stage1 PARTIAL default_results",
            strict_emit_ok=False, native_compile_ok=False, native_query_executed=False,
            stage_parity=False, stage1_accepted=False, complete_default_results_accepted=False,
            full_query_accepted=False, page_accepted=False)

    def command(self, name, argv, **kwargs):
        if name == "emit":
            app = self.path / "input"
            super().command("project-visible-page-dependencies", ["ruby", HERE / "tools/project_visible_page_dependencies.rb",
                HERE / "source/discourse", app], timeout=30)
            shutil.copyfile(COMPONENT / "topic_query_visible_page.rb", app / "app/models/topic_query_visible_page.rb")
            source = json.dumps(self.env["FIDELITY_SECURITY_FIXTURE_FROM"])
            consumer = '''# Labelled TEST caller of the shared partial source component.
class VisiblePageProbe
  def self.relation(options)
    TopicQueryVisiblePage.new.results(options)
  end
  def self.fixture_relation(options)
    result = relation(options)
    # Wrong TEST consumer only: retain real security/listable/deleted filters,
    # deliberately omit visibility. The actual shared component is unchanged.
    if ENV.fetch("FIDELITY_STAGE1_WRONG_FILTER", "0") == "1"
      result = SecurityProbe.relation
      result = result.limit(options[:per_page]) unless options[:limit] == false
      offset = options[:page].to_i * options[:per_page].to_i
      result = result.offset(offset) if offset > 0
    end
    result.from(%s).order("topics.id ASC")
  end
end
''' % source
            path = app / "app/models/visible_page_probe.rb"
            path.write_text(consumer)
            self.env.update(FIDELITY_VISIBLE_PAGE_COMPONENT=str(COMPONENT / "topic_query_visible_page.rb"),
                FIDELITY_VISIBLE_PAGE_EXPRESSION=str(COMPONENT / "original-expression.rb"),
                FIDELITY_VISIBLE_PAGE_CONSUMER=str(path))
            probe = self.path / "probe.rb"
            probe.write_text(probe.read_text() + "\n" + (HERE / "test/visible_page_probe.rb").read_text())
            self.evidence["stage1_component_manifest"] = json.loads((COMPONENT / "MANIFEST.json").read_text())
            self.evidence["stage1_test_consumer_sha256"] = digest(consumer.encode())
            self.prepare_next_stage_inputs(app)
        try:
            result = super().command(name, argv, **kwargs)
        finally:
            if name == "native":
                output = self.path / "native.stdout"
                text = output.read_text() if output.exists() else ""
                self.evidence["native_query_executed"] = self.query_execution_marker() in text
        if name == "emit":
            self.evidence["strict_emit_ok"] = result[0] == 0
        elif name == "native-compile":
            self.evidence["native_compile_ok"] = result[0] == 0
        return result

    def query_execution_marker(self):
        return "FIDELITY_STAGE1_QUERY_ENTER"

    def prepare_next_stage_inputs(self, app):
        # Extension seam for cumulative executable stages; Stage1 adds nothing.
        pass

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/visible_page_reference_consumer.rb", self.path / "probe.rb"]

    def provenance(self):
        super().provenance()
        manifest = json.loads((COMPONENT / "MANIFEST.json").read_text())
        source = (HERE / "source/discourse" / manifest["source"]).read_bytes()
        assert digest(source) == manifest["source_sha256"]
        assert digest((COMPONENT / "topic_query_visible_page.rb").read_bytes()) == manifest["candidate_sha256"]
        assert digest((COMPONENT / "original-expression.rb").read_bytes()) == manifest["original_expression_sha256"]
        for span in manifest["selected_statements"] + manifest["whole_method_dependencies"]:
            assert digest(source[span["start_byte"]:span["end_byte"]]) == span["text_sha256"]
        prior = self.evidence.get("stage1_component_manifest")
        assert prior is None or prior == manifest
        target = self.path / "input/app/models/topic_query_visible_page.rb"
        if target.exists():
            assert digest(target.read_bytes()) == manifest["candidate_sha256"]

    def stage1_controls(self):
        native = self.records("native")
        scenarios = {record["name"]: record for record in native if record.get("kind") == "stage1_rows"}
        assert len(scenarios) == 8 and scenarios["live_page0"]["rows"], "no new nonempty live materialization"
        expected = {"fixture_default": [101, 105, 108, 109, 110], "fixture_page0": [101, 105],
            "fixture_page1": [108, 109], "fixture_page2": [110], "fixture_per3": [109, 110],
            "fixture_unlimited": [101, 105, 108, 109, 110]}
        for name, ids in expected.items():
            assert [row["id"] for row in scenarios[name]["rows"]] == ids, name
        complete = scenarios["fixture_default"]["rows"]
        assert all(row["visible"] is True and row["deleted_at"] is None and row["archetype"] != "private_message" for row in complete)
        assert next(row for row in complete if row["id"] == 108)["category_id"] is None
        assert next(row for row in complete if row["id"] == 109)["category_name"] is None
        assert len([record for record in native if record.get("kind") == "stage1_refusal"]) == 7
        self.evidence["stage1_materialized"] = scenarios
        controls = {}
        for kind in ("FILTER", "PAGE", "TYPE"):
            key = "FIDELITY_STAGE1_WRONG_" + kind
            self.env[key] = "1"
            try:
                self.command("native-wrong-" + kind.lower(), [self.path / "probe"], timeout=60)
                self.command("compat-wrong-" + kind.lower(), ["bundle", "exec", "ruby", "--enable-frozen-string-literal",
                    self.path / "compat/entry.rb"], cwd=ROOT / "discourse", timeout=60)
            finally:
                del self.env[key]
            wrong = self.records("native-wrong-" + kind.lower())
            equal_records(wrong, self.records("compat-wrong-" + kind.lower()))
            if kind == "FILTER":
                fixture = next(record for record in wrong if record.get("kind") == "stage1_rows" and record["name"] == "fixture_default")
                assert [row["id"] for row in fixture["rows"]] == [101, 103, 105, 107, 108, 109, 110]
                assert next(row for row in fixture["rows"] if row["id"] == 103)["visible"] is False
                assert next(row for row in fixture["rows"] if row["id"] == 107)["visible"] is None
            elif kind == "PAGE":
                fixture = next(record for record in wrong if record.get("kind") == "stage1_rows" and record["name"] == "fixture_page0")
                assert [row["id"] for row in fixture["rows"]] == [108, 109]
            try:
                equal_records(self.records("rails-oracle"), wrong)
            except AssertionError:
                controls[kind.lower()] = True
            else:
                raise AssertionError("wrong stage1 " + kind + " was accepted")
        self.evidence["stage1_negative_controls_rejected"] = controls


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = VisiblePageRun()
    try:
        run.provenance()
        run.generate()
        run.oracle()  # Genuine original first; owned fixture/endpoint/cleanup guards.
        run.run_partial()  # Native/same-lowered CRuby + cumulative Stage0 controls.
        for name in ("native", "compat"):
            expected, actual = boot_record(run.path / "rails-oracle.stdout"), boot_record(run.path / (name + ".stdout"))
            equal_records([expected["value"], expected["ruby_class"]], [actual["value"], actual["ruby_class"]])
        run.evidence["rails_parity"] = run.compare_oracle(run.records("rails-oracle"))
        run.stage1_controls()
        run.provenance()
        assert run.evidence["oracle_cleanup_verified"] and run.evidence["native_query_executed"]
        run.evidence.update(status="PASSED_progressive_stage1_partial_visible_page_relation_ONLY", stage_parity=True,
            stage1_accepted=True, ordering_scope="deterministic TEST id order; production ordering NOT proved",
            complete_default_results_accepted=False, full_query_accepted=False, page_accepted=False)
        print(f"PASS Stage1 PARTIAL visible/paged relation ONLY. Evidence: {run.path}")
    except BaseException as error:
        run.evidence.update(status="FAILED_progressive_stage1", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
