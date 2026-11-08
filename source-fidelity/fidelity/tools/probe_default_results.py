#!/usr/bin/env python3
"""Stage2: execute supported anonymous core default_results, cumulatively.

Actual ordering/default/category/no-tags/id/count filtering and association
hydration; unsupported request and live feature profiles refuse explicitly.
Not latest_results, TopicList, a JSON request or a page.
"""
import json
import os
import shutil

from probe_visible_page import VisiblePageRun
from probe_portable_security import boot_record
from latest_model_schema import schema
from verify import ROOT, HERE, digest, equal_records

COMPONENT = HERE / "progressive/stage2"


class DefaultResultsRun(VisiblePageRun):
    def __init__(self):
        super().__init__()
        self.evidence.update(stage=__doc__, profile="progressive Stage2 supported anonymous default_results",
            stage2_accepted=False, complete_default_results_accepted=False, full_query_accepted=False, page_accepted=False)

    def query_execution_marker(self):
        return "FIDELITY_STAGE2_QUERY_ENTER"

    def schema(self):
        text = schema(self, tables=("topics", "categories", "tags", "topic_tags"))
        self.schema_rows = self.evidence["latest_model_catalog"]["rows"]
        self.evidence["schema"] = {"columns": len(self.schema_rows), "read_only_catalog": True, "runtime_values_captured": False}
        return text

    def prepare_next_stage_inputs(self, app):
        self.command("project-default-results-dependencies", ["ruby", HERE / "tools/project_default_results_dependencies.rb",
            HERE / "source/discourse", app], timeout=30)
        shutil.copyfile(COMPONENT / "topic_query_default_results.rb", app / "app/models/topic_query_default_results.rb")
        fixture = self.env["FIDELITY_SECURITY_FIXTURE_FROM"]
        # SELECT-only test data changes, never production ordering/query code.
        replacements = {
            'seed.bumped_at AS "bumped_at"': '(TIMESTAMP \'2024-02-03\' + controls.case_id * INTERVAL \'1 second\') AS "bumped_at"',
            'TIMESTAMP \'2024-02-03 04:05:06.123456\' AS "created_at"': '(TIMESTAMP \'2024-02-03\' + controls.case_id * INTERVAL \'2 seconds\') AS "created_at"',
            'seed.views AS "views"': '(200 - controls.case_id)::integer AS "views"',
            'seed.posts_count AS "posts_count"': '(controls.case_id - 100)::integer AS "posts_count"',
        }
        for old, new in replacements.items():
            assert fixture.count(old) == 1, old
            fixture = fixture.replace(old, new)
        self.evidence["stage2_select_only_fixture"] = {"sql": fixture, "production_ordering_used": True,
            "source_field_variations": replacements, "writes_or_ddl": False}
        consumer = '''# TEST-only calls/observations of the shared supported source component.
class DefaultResultsProbe
  def self.build(options)
    TopicQueryDefaultResults.new(options)
  end
  def self.results(query, options)
    query.results(options)
  end
  def self.fixture(relation)
    relation.from(%s)
  end
  def self.category_id
    SecurityProbe.relation.order("topics.id ASC").first.category_id
  end
  def self.category_slug
    Category.find(category_id).slug
  end
  def self.restricted_category_id
    Category.where(read_restricted: true).order(:id).pick(:id)
  end
  def self.other_category_id
    Category.where(read_restricted: false).where.not(id: category_id).order(:id).pick(:id)
  end
  def self.tags_loaded(record)
    record.tags_loaded?
  end
end
''' % json.dumps(fixture)
        path = app / "app/models/default_results_probe.rb"
        path.write_text(consumer)
        self.env.update(FIDELITY_DEFAULT_RESULTS_COMPONENT=str(COMPONENT / "topic_query_default_results.rb"),
            FIDELITY_DEFAULT_RESULTS_CONSUMER=str(path))
        probe = self.path / "probe.rb"
        probe.write_text(probe.read_text() + "\n" + (HERE / "test/default_results_probe.rb").read_text())
        self.evidence["stage2_component_manifest"] = json.loads((COMPONENT / "MANIFEST.json").read_text())
        self.evidence["stage2_test_consumer_sha256"] = digest(consumer.encode())
        self.prepare_latest_stage_inputs(app)

    def prepare_latest_stage_inputs(self, app):
        pass

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/default_results_reference_consumer.rb", self.path / "probe.rb"]

    def provenance(self):
        super().provenance()
        manifest = json.loads((COMPONENT / "MANIFEST.json").read_text())
        source = (HERE / "source/discourse" / manifest["source"]).read_bytes()
        assert digest(source) == manifest["source_sha256"]
        assert digest((COMPONENT / "topic_query_default_results.rb").read_bytes()) == manifest["candidate_sha256"]
        assert digest((HERE / "compat/discourse/app/models/category.rb").read_bytes()) == manifest["readonly_category_candidate_sha256"]
        for span in [manifest["original_method"], *manifest["guarded_branches"], *manifest["dependencies"]]:
            assert digest(source[span["start_byte"]:span["end_byte"]]) == span["text_sha256"]
        prior = self.evidence.get("stage2_component_manifest")
        assert prior is None or prior == manifest
        target = self.path / "input/app/models/topic_query_default_results.rb"
        if target.exists():
            assert digest(target.read_bytes()) == manifest["candidate_sha256"]

    def stage2_controls(self):
        native = self.records("native")
        scenarios = {record["name"]: record for record in native if record.get("kind") == "stage2_rows"}
        assert len(scenarios) == 17 and scenarios["live_default"]["rows"], "no complete default_results materialization"
        assert not scenarios["live_restricted_category"]["rows"], "anonymous restricted category request leaked rows"
        expected = {"fixture_default": [110, 109, 108, 105, 101], "fixture_page0": [110, 109],
            "fixture_page1": [108, 105], "fixture_views": [101, 105, 108, 109, 110],
            "fixture_created": [101, 105, 108, 109, 110], "fixture_category": [110, 105, 101],
            "fixture_except": [109, 108, 101], "fixture_ids": [110, 108, 101], "fixture_max_posts": [108, 105, 101]}
        for name, ids in expected.items():
            assert [row["id"] for row in scenarios[name]["rows"]] == ids, name
        assert len([record for record in native if record.get("kind") == "stage2_refusal"]) == 9
        self.evidence["stage2_materialized"] = scenarios
        self.evidence["stage2_materialized_tag_rows"] = sum(len(row["tags"]) for record in scenarios.values() for row in record["rows"])
        self.evidence["stage2_nonempty_tag_hydration_proved"] = self.evidence["stage2_materialized_tag_rows"] > 0
        self.evidence["stage2_coverage_limits"] = ["supported anonymous profiles only", "nested/localization profiles explicitly refuse",
            "distributed category read-cache effects not claimed", "nonempty tag membership coverage requires actual available rows"]
        rejected = {}
        for kind in ("ORDER", "CATEGORY"):
            key = "FIDELITY_STAGE2_WRONG_" + kind
            self.env[key] = "1"
            try:
                self.command("native-wrong-stage2-" + kind.lower(), [self.path / "probe"], timeout=60)
                self.command("compat-wrong-stage2-" + kind.lower(), ["bundle", "exec", "ruby", "--enable-frozen-string-literal", self.path / "compat/entry.rb"], cwd=ROOT / "discourse", timeout=60)
            finally:
                del self.env[key]
            wrong = self.records("native-wrong-stage2-" + kind.lower())
            equal_records(wrong, self.records("compat-wrong-stage2-" + kind.lower()))
            name = "fixture_default" if kind == "ORDER" else "fixture_category"
            rows = next(record["rows"] for record in wrong if record.get("kind") == "stage2_rows" and record["name"] == name)
            assert [row["id"] for row in rows] != expected[name], "negative did not alter actual query rows"
            try:
                equal_records(self.records("rails-oracle"), wrong)
            except AssertionError:
                rejected[kind.lower()] = True
            else:
                raise AssertionError("wrong default_results " + kind + " accepted")
        self.evidence["stage2_negative_controls_rejected"] = rejected


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = DefaultResultsRun()
    try:
        run.provenance()
        run.generate()
        run.oracle()
        run.run_partial()
        for name in ("native", "compat"):
            expected, actual = boot_record(run.path / "rails-oracle.stdout"), boot_record(run.path / (name + ".stdout"))
            equal_records([expected["value"], expected["ruby_class"]], [actual["value"], actual["ruby_class"]])
        run.evidence["rails_parity"] = run.compare_oracle(run.records("rails-oracle"))
        run.stage1_controls()
        run.stage2_controls()
        run.provenance()
        assert "FIDELITY_STAGE2_MATERIALIZED" in (run.path / "native.stdout").read_text()
        assert run.evidence["oracle_cleanup_verified"]
        run.evidence.update(status="PASSED_progressive_stage2_supported_anonymous_default_results_ONLY",
            stage_parity=True, stage1_accepted=True, stage2_accepted=True, complete_default_results_accepted=True,
            full_query_accepted=False, page_accepted=False)
        print(f"PASS Stage2 supported anonymous default_results ONLY. Evidence: {run.path}")
    except BaseException as error:
        run.evidence.update(status="FAILED_progressive_stage2", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
