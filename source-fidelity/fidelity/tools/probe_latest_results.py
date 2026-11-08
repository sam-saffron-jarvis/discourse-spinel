#!/usr/bin/env python3
"""Stage3a: RUN supported anonymous latest_results and real result callbacks.

Cumulative Stage0/1/2. Not list_latest/TopicList hydration, a request or page.
"""
import json
import os
import shutil

from probe_default_results import DefaultResultsRun
from probe_portable_security import boot_record
from verify import ROOT, HERE, digest, equal_records

COMPONENT = HERE / "progressive/stage3a"


class LatestResultsRun(DefaultResultsRun):
    def __init__(self):
        super().__init__()
        self.evidence.update(stage=__doc__, profile="progressive Stage3a supported anonymous latest_results",
            latest_results_accepted=False, list_hydration_accepted=False, full_query_accepted=False, page_accepted=False)

    def query_execution_marker(self):
        return "FIDELITY_STAGE3A_QUERY_ENTER"

    def prepare_latest_stage_inputs(self, app):
        self.command("project-latest-result-callback-registry", ["ruby", HERE / "tools/project_latest_results_dependencies.rb",
            HERE / "source/discourse", app], timeout=30)
        shutil.copyfile(COMPONENT / "topic_query_latest_results.rb", app / "app/models/topic_query_latest_results.rb")
        consumer = '''# TEST calls, not query/permission/callback replacements.
class LatestResultsProbe
  def self.build(options)
    TopicQueryLatestResults.new(options)
  end
  def self.results(query, options)
    query.latest_results(options)
  end
end
'''
        path = app / "app/models/latest_results_probe.rb"
        path.write_text(consumer)
        self.env.update(FIDELITY_LATEST_RESULTS_COMPONENT=str(COMPONENT / "topic_query_latest_results.rb"),
            FIDELITY_LATEST_RESULTS_CONSUMER=str(path))
        probe = self.path / "probe.rb"
        probe.write_text(probe.read_text() + "\n" + (HERE / "test/latest_results_probe.rb").read_text())
        self.evidence["stage3a_component_manifest"] = json.loads((COMPONENT / "MANIFEST.json").read_text())
        self.evidence["stage3a_test_consumer_sha256"] = digest(consumer.encode())
        self.prepare_list_stage_inputs(app)

    def prepare_list_stage_inputs(self, app):
        pass

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/latest_results_reference_consumer.rb", self.path / "probe.rb"]

    def provenance(self):
        super().provenance()
        manifest = json.loads((COMPONENT / "MANIFEST.json").read_text())
        source = (HERE / "source/discourse" / manifest["source"]).read_bytes()
        assert digest(source) == manifest["source_sha256"]
        assert digest((COMPONENT / "topic_query_latest_results.rb").read_bytes()) == manifest["candidate_sha256"]
        for span in manifest["methods"] + manifest["guarded_source_changes"]:
            assert digest(source[span["start_byte"]:span["end_byte"]]) == span["text_sha256"]
        prior = self.evidence.get("stage3a_component_manifest")
        assert prior is None or prior == manifest
        target = self.path / "input/app/models/topic_query_latest_results.rb"
        if target.exists():
            assert digest(target.read_bytes()) == manifest["candidate_sha256"]

    def latest_controls(self):
        scenarios = {record["name"]: record for record in self.records("native") if record.get("kind") == "stage3a_rows"}
        assert len(scenarios) == 6 and scenarios["live_latest"]["rows"], "no new nonempty latest_results rows"
        self.evidence["stage3a_materialized"] = scenarios
        base = [row["id"] for row in scenarios["fixture_latest"]["rows"]]
        filtered = [row["id"] for row in scenarios["fixture_callback"]["rows"]]
        assert 110 in base and filtered == [id for id in base if id != 110], "actual result-filter callback did not change rows"
        assert scenarios["fixture_callback"]["callback_unit"] is True
        self.env["FIDELITY_STAGE3A_WRONG_CALLBACK"] = "1"
        try:
            self.command("native-wrong-callback", [self.path / "probe"], timeout=60)
            self.command("compat-wrong-callback", ["bundle", "exec", "ruby", "--enable-frozen-string-literal",
                self.path / "compat/entry.rb"], cwd=ROOT / "discourse", timeout=60)
        finally:
            del self.env["FIDELITY_STAGE3A_WRONG_CALLBACK"]
        wrong = self.records("native-wrong-callback")
        equal_records(wrong, self.records("compat-wrong-callback"))
        rows = next(record["rows"] for record in wrong if record.get("kind") == "stage3a_rows" and record["name"] == "fixture_callback")
        assert [row["id"] for row in rows] == base and [row["id"] for row in rows] != filtered
        try:
            equal_records(self.records("rails-oracle"), wrong)
        except AssertionError:
            self.evidence["stage3a_wrong_callback_rejected"] = True
        else:
            raise AssertionError("ignored result callback accepted")
        settings = scenarios["live_latest"]
        self.evidence["stage3a_nonempty_mute_settings_exercised"] = bool(settings["default_categories_muted"] or settings["default_tags_muted"] or settings["mute_all_categories_by_default"])


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = LatestResultsRun()
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
        run.latest_controls()
        run.provenance()
        assert "FIDELITY_STAGE3A_MATERIALIZED" in (run.path / "native.stdout").read_text()
        assert run.evidence["oracle_cleanup_verified"]
        run.evidence.update(status="PASSED_progressive_stage3a_supported_anonymous_latest_results_ONLY",
            stage_parity=True, stage1_accepted=True, stage2_accepted=True, complete_default_results_accepted=True,
            latest_results_accepted=True, list_hydration_accepted=False, full_query_accepted=False, page_accepted=False)
        print(f"PASS Stage3a supported anonymous latest_results ONLY. Evidence: {run.path}")
    except BaseException as error:
        run.evidence.update(status="FAILED_progressive_stage3a", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
