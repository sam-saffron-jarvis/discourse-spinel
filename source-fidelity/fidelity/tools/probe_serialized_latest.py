#!/usr/bin/env python3
"""Cumulative executable full latest SERIALIZER experiment, NOT a JSON request.

Defaults to compile AND RUN. Refusal/nonzero/parity failure exits nonzero. Even
success here cannot accept controller/status/headers/paging or a browser page.
"""
import json
import os
import shutil
import re

from probe_list_latest import ListLatestRun
from probe_portable_security import boot_record
from latest_model_schema import schema
from verify import ROOT, HERE, digest, equal_records
from serialization_source_audit import audit as audit_serialization_sources


class SerializedLatestRun(ListLatestRun):
    additional_schema_tables = ()
    def __init__(self):
        super().__init__()
        self.evidence.update(stage=__doc__, profile="shared AMS0.8 full latest serialization experiment",
            full_serialized_list_accepted=False, json_request_accepted=False, full_query_accepted=False, page_accepted=False)

    def command(self, name, argv, **kwargs):
        if name == "native-compile":
            # First whole-serializer native frontend exceeded the smaller
            # list-only window. Measure phases once; failure remains nonzero.
            kwargs["timeout"] = 360
            argv = list(argv)
            argv.insert(1, "--timing")
        return super().command(name, argv, **kwargs)

    def schema(self):
        text = schema(self, tables=("topics", "categories", "tags", "topic_tags", "users", "groups", "posts",
            "uploads", "topic_thumbnails", "optimized_images", "topic_custom_fields", "themes", "child_themes",
            "remote_themes", "theme_modifier_sets") + self.additional_schema_tables)
        self.schema_rows = self.evidence["latest_model_catalog"]["rows"]
        return text

    def generate(self):
        super().generate()
        entry = self.path / "entry.rb"
        text = entry.read_text()
        # Execute the actual application initializer's declared zone through
        # the existing framework runtime. Never inherit the probe host's TZ.
        application_source = (HERE / "source/discourse/config/application.rb").read_text()
        zones = re.findall(r'^    config\.time_zone = ("[^"\n]+")$', application_source, re.MULTILINE)
        assert len(zones) == 1, "application timezone initialization source changed"
        timezone_boot = "ActiveSupport.set_default_zone(" + zones[0] + ")\n"
        assert text.count('Db.configure(') == 1
        text = text.replace('Db.configure(', timezone_boot + 'Db.configure(')
        self.evidence["serialization_application_timezone_boot"] = {
            "source": "config/application.rb", "sha256": digest(application_source.encode()),
            "declaration": "config.time_zone = " + zones[0], "bootstrap": timezone_boot,
            "effective_runtime_value_captured": False}
        core = HERE / "compat/discourse/lib/site_settings/portable_core_readers.rb"
        prefix = "require " + json.dumps(str(core)) + "\nSiteSetting.extend(SiteSettings::PortableCoreReaders)\n"
        anchor = "SiteSetting.extend(SiteSettings::PortableSettingsContext)"
        assert text.count(anchor) == 1
        entry.write_text(text.replace(anchor, prefix + anchor))
        upload = HERE / "compat/discourse/lib/site_settings/portable_upload_readers.rb"
        upload_source = "require " + json.dumps(str(upload)) + "\nSiteSetting.extend(SiteSettings::PortableUploadReaders)\n"
        text = entry.read_text()
        marker = "SiteSetting.extend(SiteSettings::PortableScalarReaders)"
        assert text.count(marker) == 1
        entry.write_text(text.replace(marker, marker + "\n" + upload_source))
        text = entry.read_text()
        presentation = HERE / "compat/discourse/lib/portable_letter_avatar_version.rb"
        palette = HERE / "compat/discourse/lib/portable_avatar_palette.rb"
        text = "require " + json.dumps(str(presentation)) + "\nrequire " + json.dumps(str(palette)) + "\n" + text
        # Requires declare actual read implementations only; endpoint policy
        # still precedes every DB connection. Neither declaration executes I/O.
        entry.write_text(text)
        self.evidence["serialization_external_read_implementations"] = {str(path.relative_to(HERE)): digest(path.read_bytes())
            for path in (presentation, palette)}
        self.evidence["serialization_actual_core_readers"] = {"sha256": digest(core.read_bytes()),
            "unsupported_special_getters_refuse": True, "fake_values_or_permission_interface": False}
        for name, expected in self.evidence.get("serialization_source_assets", {}).items():
            source = self.path / "input" / name
            assert digest(source.read_bytes()) == expected
            target = self.path / "emitted" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    def query_execution_marker(self):
        return "FIDELITY_SERIALIZED_LIST_QUERY_ENTER"

    def prepare_serialization_stage_inputs(self, app):
        manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
        candidates_path = app / "candidate-model-projections.json"
        candidates = json.loads(candidates_path.read_text())
        for name, expected in manifest["candidate_source_sha256"].items():
            source_name = name.removeprefix("discourse/")
            if not (source_name.startswith("app/serializers/") or source_name == "lib/portable_serializer_read.rb"):
                continue
            source = HERE / "compat" / name
            assert digest(source.read_bytes()) == expected
            target = app / source_name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            # Serde source is audited separately from original model projections.
            # Library input paths are retained here; no fake original map entry.
            self.evidence.setdefault("serialization_shared_inputs", {})[source_name] = expected
        palette_source = HERE / "compat/discourse/lib/portable_avatar_palette.rb"
        palette_target = app / "app/models/portable_avatar_palette.rb"
        shutil.copyfile(palette_source, palette_target)
        palette_sha = digest(palette_source.read_bytes())
        candidates.append({"source_root": "compat/discourse", "source": "lib/portable_avatar_palette.rb",
            "generated": "app/models/portable_avatar_palette.rb", "source_sha256": palette_sha, "generated_sha256": palette_sha,
            "selected_spans": [{"start_byte": 0, "end_byte": len(palette_source.read_bytes()), "text_sha256": palette_sha}],
            "limitation": "Actual pinned source palette data only, not observed avatar colors"})
        candidates_path.write_text(json.dumps(candidates, indent=2) + "\n")
        encoder_source = HERE / "compat/discourse/lib/portable_avatar_encoding.rb"
        shutil.copyfile(encoder_source, app / "app/models/portable_avatar_encoding.rb")
        encoder_sha = digest(encoder_source.read_bytes())
        candidates.append({"source_root": "compat/discourse", "source": "lib/portable_avatar_encoding.rb",
            "generated": "app/models/portable_avatar_encoding.rb", "source_sha256": encoder_sha, "generated_sha256": encoder_sha,
            "selected_spans": [{"start_byte": 0, "end_byte": len(encoder_source.read_bytes()), "text_sha256": encoder_sha}],
            "limitation": "Actual default Addressable byte-encoding contract for String avatar names"})
        candidates_path.write_text(json.dumps(candidates, indent=2) + "\n")
        self.command("project-serializer-read-dependencies", ["ruby", HERE / "tools/project_serializer_dependencies.rb",
            HERE / "source/discourse", app, HERE / "compat/discourse"], timeout=30)
        for source in (HERE / "compat/discourse/config/portable_emoji_source").glob("*.json"):
            target = app / "config/portable_emoji_source" / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            self.evidence.setdefault("serialization_source_assets", {})[str(target.relative_to(app))] = digest(source.read_bytes())
        signature = "discourse/sig/portable_scalar_readers.rbs"
        scalar_source = HERE / "compat" / signature
        assert digest(scalar_source.read_bytes()) == manifest["candidate_source_sha256"][signature]
        (app / "sig").mkdir(exist_ok=True)
        shutil.copyfile(scalar_source, app / "sig/portable_scalar_readers.rbs")
        contracts = """# Source-owned finite tag-count helper contracts; no data/identity values.
class SiteSetting
  def self.logo_small: () -> (Upload | nil)
  def self.portable_rendering_hostname: () -> String
  def self.portable_rendering_base_path: () -> String
  def self.portable_avatar_cdn_url: (String url) -> String
end
class PortableLetterAvatarVersion
  def self.version: () -> String
end
class Tag
  def self.topic_count_column: (Guardian guardian) -> String
  def self.topic_count_for: (Tag tag, Guardian guardian) -> Integer
end
"""
        (app / "sig/serialized_latest_read_contracts.rbs").write_text(contracts)
        self.evidence["serialization_read_contracts"] = {"sha256": digest(contracts.encode()), "supplies_values_or_identity": False}
        # Baseline factory and actual shared list remain unchanged. The setting
        # dependency is precisely the original latest action's no-definitions
        # option, not a captured effective value or custom topic backend.
        consumer = '''class LatestSerializationProbe
  def self.payload
    options = {no_definitions: !SiteSetting.show_category_definitions_in_topic_lists}
    query = ListLatestProbe.build(options)
    list = ListLatestProbe.list(query)
    list.topics.each do |row|
      raise ArgumentError, "unsupported readonly null-slug serialization" if row.read_attribute(:slug).nil?
      raise ArgumentError, "unsupported readonly uncached fancy title" if row.read_attribute(:fancy_title).nil?
    end
    TopicListSerializer.new(list, scope: query.guardian).as_json
  end
end
'''
        path = app / "app/models/latest_serialization_probe.rb"
        path.write_text(consumer)
        self.env["FIDELITY_SERIALIZATION_CONSUMER"] = str(path)
        probe = self.path / "probe.rb"
        probe.write_text(probe.read_text() + '''
puts "FIDELITY_SERIALIZED_LIST_QUERY_ENTER"
serialized_latest = LatestSerializationProbe.payload
# Use the real framework JSON contract for temporal leaves, not the TEST
# driver's raw Time#to_s fallback. This is still NOT a controller request.
serialized_json = ActiveSupport::JSON.encode(serialized_latest)
puts "FIDELITY " + FidelityDriver.encode({kind: "full_serialized_latest", body: ActiveSupport::JSON.decode(serialized_json)})
puts "FIDELITY_SERIALIZED_LIST_MATERIALIZED"
''')
        self.evidence["serialization_consumer_sha256"] = digest(consumer.encode())

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/serialized_latest_reference_consumer.rb", self.path / "probe.rb"]

    def serialization_controls(self):
        native = self.records("native")
        record = next(row for row in native if row.get("kind") == "full_serialized_latest")
        body = record["body"]
        assert set(body) == {"topic_list", "users", "primary_groups", "flair_groups"}
        assert body["topic_list"]["topics"] and body["users"] and body["primary_groups"] and body["flair_groups"]
        assert len({user["id"] for user in body["users"]}) == len(body["users"]), "duplicate side-loaded users"
        for topic in body["topic_list"]["topics"]:
            assert type(topic["id"]) is int and type(topic["visible"]) is bool
            assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z", topic["created_at"])
        reference = self.records("rails-oracle")
        for name in ("omitted_side_load", "wrong_boolean_type", "wrong_time_precision", "omitted_topic_field"):
            wrong = json.loads(json.dumps(native))
            changed = next(row["body"] for row in wrong if row.get("kind") == "full_serialized_latest")
            if name == "omitted_side_load":
                del changed["users"]
            elif name == "wrong_boolean_type":
                changed["users"][0]["admin"] = int(changed["users"][0]["admin"])
            elif name == "wrong_time_precision":
                changed["topic_list"]["topics"][0]["created_at"] = changed["topic_list"]["topics"][0]["created_at"].replace("Z", "000Z")
            else:
                del changed["topic_list"]["topics"][0]["posts_count"]
            try:
                equal_records(reference, wrong)
            except AssertionError:
                self.evidence["serialization_" + name + "_rejected"] = True
            else:
                raise AssertionError("incorrect complete serialized payload accepted: " + name)
        self.evidence["serialization_coverage"] = {
            "topics": len(body["topic_list"]["topics"]), "side_loaded_users": len(body["users"]),
            "primary_groups": len(body["primary_groups"]), "flair_groups": len(body["flair_groups"]),
            "complete_original_payload_compared": True, "time_format": "actual framework JSON UTC milliseconds",
            "request_status_headers_paging_accepted": False,
            "unproved": ["nonempty tags/images/thumbnails/custom fields", "authenticated/localized/status profiles",
                "non-ASCII usernames", "activated serializer caches", "configured CDN", "nondevelopment/multisite routing"]}

    def provenance(self):
        super().provenance()
        reports = audit_serialization_sources()
        previous = self.evidence.get("serialization_source_manifests")
        assert previous is None or previous == reports, "serializer sources changed during execution"
        self.evidence["serialization_source_manifests"] = reports
        if self.evidence.get("serialization_application_timezone_boot"):
            report = self.evidence["serialization_application_timezone_boot"]
            assert digest((HERE / "source/discourse" / report["source"]).read_bytes()) == report["sha256"]
        for name, expected in self.evidence.get("serialization_external_read_implementations", {}).items():
            assert digest((HERE / name).read_bytes()) == expected
        for name, expected in self.evidence.get("serialization_source_assets", {}).items():
            assert digest((self.path / "input" / name).read_bytes()) == expected
            assert digest((self.path / "emitted" / name).read_bytes()) == expected
        addition = self.path / "input/serialization-list-read-addition.json"
        if addition.exists():
            report = json.loads(addition.read_text())
            source = (HERE / "source/discourse" / report["source"]).read_bytes()
            assert digest(source) == report["source_sha256"]
            assert digest(source[report["start_byte"]:report["end_byte"]]) == report["text_sha256"]
            assert digest((addition.parent / "app/models/topic_list_serialization_reads.rb").read_bytes()) == report["generated_sha256"]
            self.evidence["serialization_list_read_addition"] = report
        candidate_path = self.path / "input/candidate-model-projections.json"
        projected = {item["generated"] for item in json.loads(candidate_path.read_text())} if candidate_path.exists() else set()
        for name, expected in self.evidence.get("serialization_shared_inputs", {}).items():
            assert digest((HERE / "compat/discourse" / name).read_bytes()) == expected
            if name not in projected:
                assert digest((self.path / "input" / name).read_bytes()) == expected


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = SerializedLatestRun()
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
        run.serialization_controls()
        run.provenance()
        record = next(row for row in run.records("native") if row.get("kind") == "full_serialized_latest")
        assert record["body"]["topic_list"]["topics"] and record["body"]["users"]
        assert "FIDELITY_SERIALIZED_LIST_MATERIALIZED" in (run.path / "native.stdout").read_text()
        assert run.evidence["oracle_cleanup_verified"]
        run.evidence.update(status="PASSED_full_serialized_list_ONLY_NOT_REQUEST", stage_parity=True,
            stage1_accepted=True, stage2_accepted=True, complete_default_results_accepted=True,
            latest_results_accepted=True, list_hydration_accepted=True,
            full_serialized_list_accepted=True, json_request_accepted=False, full_query_accepted=False, page_accepted=False)
        print(f"PASS full SERIALIZER ONLY; not request acceptance. Evidence: {run.path}")
    except BaseException as error:
        run.evidence.update(status="FAILED_full_serialized_list_experiment", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
