#!/usr/bin/env python3
"""Stage3b: compile AND RUN supported anonymous list_latest/TopicList hydration.

Cumulative Stage0/1/2/3a; not a controller/serializer JSON request or page.
"""
import json
import os
import shutil

from probe_latest_results import LatestResultsRun
from probe_portable_security import boot_record
from latest_model_schema import schema
from compat_source_audit import audit
from verify import ROOT, HERE, digest, equal_records

COMPONENT = HERE / "progressive/stage3b"


class ListLatestRun(LatestResultsRun):
    def __init__(self):
        super().__init__()
        self.env["RH_SQL_TRACE"] = "1"
        self.evidence.update(stage=__doc__, profile="progressive Stage3b supported anonymous list hydration",
            list_hydration_accepted=False, json_request_accepted=False, full_query_accepted=False, page_accepted=False)

    def generate(self):
        super().generate()
        entry = self.path / "entry.rb"
        text = entry.read_text()
        anchor = "setting_value = SiteSetting.suppress_secured_categories_from_admin"
        assert text.count(anchor) == 1
        live_locale = 'I18n.locale = SiteSetting.portable_store.get("default_locale", SiteSetting.portable_site)'
        entry.write_text(text.replace(anchor, live_locale + "\n" + anchor))
        self.evidence["stage3b_locale_bootstrap"] = {"source": live_locale,
            "live_shared_store_read": True, "forced_locale_or_snapshot": False,
            "unsupported_locales_refuse": True}

    def query_execution_marker(self):
        return "FIDELITY_STAGE3B_QUERY_ENTER"

    def schema(self):
        text = schema(self, tables=("topics", "categories", "tags", "topic_tags", "users", "groups", "posts",
            "uploads", "topic_thumbnails", "optimized_images", "topic_custom_fields"))
        self.schema_rows = self.evidence["latest_model_catalog"]["rows"]
        self.evidence["schema"] = {"columns": len(self.schema_rows), "read_only_catalog": True, "runtime_values_captured": False}
        return text

    def prepare_list_stage_inputs(self, app):
        self.command("project-list-latest-read-dependencies", ["ruby", HERE / "tools/project_list_latest_dependencies.rb",
            HERE / "source/discourse", app, HERE / "compat/discourse"], timeout=30)
        self.command("project-list-custom-field-read-dependencies", ["ruby", HERE / "tools/project_latest_custom_fields.rb",
            HERE / "source/discourse", app], timeout=30)
        lock = json.loads((HERE / "SOURCE_LOCK.json").read_text())
        framework = next(group for group in lock["framework_sources"] if group["gem"] == "activemodel")
        serialization = next(item for item in framework["files"] if item["package_member"] == "lib/active_model/serialization.rb")
        framework_source = HERE / serialization["path"]
        assert digest(framework_source.read_bytes()) == serialization["sha256"]
        target = app / "app/models/active_model_serialization.rb"
        shutil.copyfile(framework_source, target)
        resources = {"app/models/active_model_serialization.rb": {"source": serialization["path"], "sha256": serialization["sha256"]}}
        for name in ("server.en.yml", "client.en.yml", "server.fr.yml", "client.fr.yml"):
            source = HERE / "source/discourse/config/locales" / name
            target = app / "config/locales" / name
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(source, target)
            resources[str(target.relative_to(app))] = {"source": "source/discourse/config/locales/" + name, "sha256": digest(source.read_bytes())}
        self.evidence["stage3b_source_resources"] = resources
        for name in ("topic_query_list_latest.rb", "topic_list.rb"):
            shutil.copyfile(COMPONENT / name, app / "app/models" / name)
        fixture = self.evidence["stage2_select_only_fixture"]["sql"]
        changes = {'seed.pinned_globally AS "pinned_globally"': '(controls.case_id = 101) AS "pinned_globally"',
            'seed.pinned_at AS "pinned_at"': '(CASE WHEN controls.case_id = 101 THEN TIMESTAMP \'2024-02-04\' ELSE NULL::timestamp END) AS "pinned_at"',
            'seed.featured_user1_id AS "featured_user1_id"': '(SELECT u.id FROM public.users u WHERE u.id <> seed.user_id ORDER BY u.id LIMIT 1) AS "featured_user1_id"',
            'seed.featured_user3_id AS "featured_user3_id"': 'seed.user_id AS "featured_user3_id"'}
        for old, new in changes.items():
            assert fixture.count(old) == 1, old
            fixture = fixture.replace(old, new)
        self.evidence["stage3b_select_only_pinning_fixture"] = {"sql": fixture, "writes_or_ddl": False, "changes": changes}
        consumer = '''# TEST caller only; real source query/list/hydration implementations.
class ListLatestProbe
  def self.build(options)
    TopicQueryListLatest.new(options)
  end
  def self.list(query)
    query.list_latest
  end
  def self.fixture(relation)
    relation.from(%s)
  end
  def self.loaded(record)
    record.category_loaded? && record.image_upload_loaded? && record.topic_thumbnails_loaded? && record.first_post_loaded?
  end
end
''' % json.dumps(fixture)
        path = app / "app/models/list_latest_probe.rb"
        path.write_text(consumer)
        self.env.update(FIDELITY_LIST_LATEST_COMPONENT=str(COMPONENT / "topic_query_list_latest.rb"),
            FIDELITY_LIST_LATEST_CONSUMER=str(path))
        probe = self.path / "probe.rb"
        probe.write_text(probe.read_text() + "\n" + (HERE / "test/list_latest_probe.rb").read_text())
        self.evidence["stage3b_component_manifest"] = json.loads((COMPONENT / "MANIFEST.json").read_text())
        self.evidence["stage3b_test_consumer_sha256"] = digest(consumer.encode())
        self.prepare_serialization_stage_inputs(app)

    def prepare_serialization_stage_inputs(self, app):
        pass

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/list_latest_reference_consumer.rb", self.path / "probe.rb"]

    def provenance(self):
        super().provenance()
        manifest = json.loads((COMPONENT / "MANIFEST.json").read_text())
        for name, sha in manifest["source_sha256"].items():
            assert digest((HERE / "source/discourse" / name).read_bytes()) == sha
        for change in manifest["guarded_changes"]:
            source = (HERE / "source/discourse" / change["source"]).read_bytes()
            assert digest(source[change["start_byte"]:change["end_byte"]]) == change["text_sha256"]
        for name, sha in manifest["candidate_sha256"].items():
            assert digest((COMPONENT / name).read_bytes()) == sha
            target = self.path / "input/app/models" / name
            if target.exists():
                assert digest(target.read_bytes()) == sha
        prior = self.evidence.get("stage3b_component_manifest")
        assert prior is None or prior == manifest
        app = self.path / "input"
        if app.exists():
            self.evidence["stage3b_candidate_projection_audit"] = audit(app)
        for name, item in self.evidence.get("stage3b_source_resources", {}).items():
            assert digest((HERE / item["source"]).read_bytes()) == item["sha256"]
            assert digest((app / name).read_bytes()) == item["sha256"]

    def list_controls(self):
        scenarios = {row["name"]: row for row in self.records("native") if row.get("kind") == "stage3b_list"}
        assert len(scenarios) == 6 and scenarios["live_list"]["rows"], "no new actual list hydration"
        assert any(row["posters"] for row in scenarios["live_list"]["rows"]), "no nonempty actual user/poster hydration"
        assert [row["id"] for row in scenarios["fixture_list"]["rows"]] == [101, 110, 109, 108, 105]
        assert [row["id"] for row in scenarios["fixture_page0"]["rows"]] == [101, 110]
        assert [row["id"] for row in scenarios["fixture_page1"]["rows"]] == [109, 108]
        assert scenarios["live_preload_unit"]["publish_read_state"] is True
        assert all(row["preloaded_custom_fields"] == {"fidelity_missing_cf": None} for row in scenarios["live_preload_unit"]["rows"])
        assert any(row["featured_user_ids"] and row["recent_user_ids"] for row in scenarios["fixture_list"]["rows"])
        self.evidence["stage3b_materialized"] = scenarios
        self.env["FIDELITY_STAGE3B_WRONG_PINNING"] = "1"
        try:
            self.command("native-wrong-pinning", [self.path / "probe"], timeout=60)
            self.command("compat-wrong-pinning", ["bundle", "exec", "ruby", "--enable-frozen-string-literal",
                self.path / "compat/entry.rb"], cwd=ROOT / "discourse", timeout=60)
        finally:
            del self.env["FIDELITY_STAGE3B_WRONG_PINNING"]
        wrong = self.records("native-wrong-pinning")
        equal_records(wrong, self.records("compat-wrong-pinning"))
        different = next(row for row in wrong if row.get("kind") == "stage3b_list" and row["name"] == "fixture_page0")
        assert [row["id"] for row in different["rows"]] != [101, 110]
        try:
            equal_records(self.records("rails-oracle"), wrong)
        except AssertionError:
            self.evidence["stage3b_wrong_pinning_rejected"] = True
        else:
            raise AssertionError("ignored pinning accepted")

        self.env["FIDELITY_STAGE3B_WRONG_PRELOAD"] = "1"
        try:
            self.command("native-wrong-preload", [self.path / "probe"], timeout=60)
            self.command("compat-wrong-preload", ["bundle", "exec", "ruby", "--enable-frozen-string-literal",
                self.path / "compat/entry.rb"], cwd=ROOT / "discourse", timeout=60)
        finally:
            del self.env["FIDELITY_STAGE3B_WRONG_PRELOAD"]
        wrong = self.records("native-wrong-preload")
        equal_records(wrong, self.records("compat-wrong-preload"))
        wrong_unit = next(row for row in wrong if row.get("kind") == "stage3b_list" and row["name"] == "live_preload_unit")
        assert wrong_unit["publish_read_state"] is False
        try:
            equal_records(self.records("rails-oracle"), wrong)
        except AssertionError:
            self.evidence["stage3b_ignored_preload_callback_rejected"] = True
        else:
            raise AssertionError("ignored list preload callback accepted")
        wrong_type = json.loads(json.dumps(self.records("native")))
        list_row = next(row for row in wrong_type if row.get("kind") == "stage3b_list" and row["name"] == "live_list")
        list_row["rows"][0]["posters"][0]["user"]["admin"] = 1
        try:
            equal_records(self.records("rails-oracle"), wrong_type)
        except AssertionError:
            self.evidence["stage3b_wrong_user_flag_type_rejected"] = True
        else:
            raise AssertionError("wrong public user flag type accepted")
        rows = [row for scenario in scenarios.values() for row in scenario["rows"]]
        self.evidence["stage3b_coverage"] = {"nonempty_first_posts": sum(row["first_post_id"] is not None for row in rows),
            "nonempty_poster_groups": sum(poster["primary_group"] is not None for row in rows for poster in row["posters"]),
            "nonempty_images": sum(row["image_upload_id"] is not None for row in rows),
            "nonempty_thumbnails": sum(len(row["thumbnails"]) for row in rows),
            "custom_field_missing_name_and_null_maps_executed": True,
            "nonempty_custom_field_values_proved": False,
            "scope": "Supported anonymous core :latest only; stored slug nonnull; en locale; no controller/serializer request",
            "unproved": ["nonempty image/thumbnail data", "nonempty custom-field values", "nonempty tag memberships",
                "authenticated notification/action/participant profiles", "optimized scoped first-post batch query counts"]}


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = ListLatestRun()
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
        run.list_controls()
        run.provenance()
        assert "FIDELITY_STAGE3B_MATERIALIZED" in (run.path / "native.stdout").read_text()
        assert run.evidence["oracle_cleanup_verified"]
        run.evidence.update(status="PASSED_progressive_stage3b_supported_anonymous_list_hydration_ONLY", stage_parity=True,
            stage1_accepted=True, stage2_accepted=True, complete_default_results_accepted=True, latest_results_accepted=True,
            list_hydration_accepted=True, json_request_accepted=False, full_query_accepted=False, page_accepted=False)
        print(f"PASS Stage3b supported anonymous list hydration ONLY. Evidence: {run.path}")
    except BaseException as error:
        run.evidence.update(status="FAILED_progressive_stage3b", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
