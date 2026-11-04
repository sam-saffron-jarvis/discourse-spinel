#!/usr/bin/env python3
"""Fail-closed ticket019 probe; a CRuby/Rails partial result is NEVER native F2.

The current source slice deliberately keeps the original admin setting send.
Until its real declaration/provider closure is executable, native compilation
refuses it. Do not install a fake getter or turn this into a successful018 alias.
"""
import json
import os
from pathlib import Path
import shutil
import sys

from verify import Run, HERE, ROOT, digest, equal_records
from source_fixture import source_fixture
import settings_closure


ENTRY = '''# frozen_string_literal: true
require_relative "emitted/runtime/sqlite_adapter"
require_relative "emitted/runtime/db"
require_relative "emitted/runtime/active_support_ext"
require_relative "emitted/runtime/active_support_duration"
require_relative "emitted/runtime/active_support_time_parsing"
require_relative "emitted/runtime/json_builder"
require_relative "emitted/runtime/active_record"
require_relative "emitted/app/models"
module FidelityDriver
  def self.capture
    Db.capture_sql { yield }
  end
  def self.category_loaded(record)
    record.category_loaded?
  end
  def self.encode(value)
    JsonBuilder.encode_value(value)
  end
  def self.timestamp(value)
    value.nil? ? nil : value.utc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ")
  end
end
Db.configure(ENV.fetch("DATABASE_URL"), pool_size: 2)
ActiveRecord.adapter = SqliteAdapter
2.times do |index|
  state = Db.pool.conn(index).client.exec("SELECT current_database(), inet_server_port(), current_setting('default_transaction_read_only')")
  raise "unsafe PG pool endpoint" unless state.getvalue(0, 0) == "discourse_development" && state.getvalue(0, 1) == "5499" && state.getvalue(0, 2) == "on"
end
Db.exec("BEGIN READ ONLY")
require_relative "probe"
Db.exec("ROLLBACK")
Db.close
'''


class TopicQueryRun(Run):
    def __init__(self):
        super().__init__("verify-topic-query")
        self.evidence["stage"] = "PARTIAL original TopicQuery category-security projection; NOT complete default_results/list_latest/F2"

    def provenance(self):
        super().provenance()
        mapping = self.path / "input/projection-map.json"
        if mapping.exists():
            for item in json.loads(mapping.read_text()):
                original = (HERE / "source/discourse" / item["source"]).read_bytes()
                generated = (self.path / "input" / item["generated"]).read_bytes()
                assert digest(original) == item["source_sha256"]
                assert digest(generated) == item["generated_sha256"]
                assert len(original) == len(generated)
                for span in item["selected_spans"]:
                    start, end = span["start_byte"], span["end_byte"]
                    assert original[start:end] == generated[start:end]
                    assert digest(generated[start:end]) == span["text_sha256"]
            assert digest((self.path / "input/topic-query-expression.rb").read_bytes()) == self.evidence["expression_sha256"]
            hashes = self.evidence.get("same_lowered_ruby", {}).get("hashes", {})
            for path, sha in hashes.items():
                assert digest((self.path / "emitted" / path).read_bytes()) == sha
            self.audit_additional_inputs()
            self.evidence["projection_and_emitted_hashes_rechecked"] = True

    def audit_additional_inputs(self):
        settings_closure.audit(HERE / "source/discourse", self.path / "settings-closure-input",
                               self.evidence["settings_closure_inputs"])

    def measure_settings_closure(self, app):
        # This separate bounded diagnostic experiment uses COMPLETE ORIGINAL
        # settings/dependency files. Its output is NEVER executed/accepted with
        # unsupported warnings; boot inventories are NOT a partial bootstrap.
        full = self.path / "settings-closure-input"
        shutil.copytree(app, full)
        manifest = settings_closure.materialize(HERE / "source/discourse", full)
        self.evidence["settings_closure_inputs"] = manifest
        (self.path / "settings-closure-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
        self.save()
        code, _ = self.command("settings-closure-emit", [ROOT / "roundhouse/target/release/roundhouse", "--target", "spinel", "--allow-unsupported", full,
                                                       "-o", self.path / "settings-closure-emitted"], check=False, timeout=120)
        diagnostic = (self.path / "settings-closure-emit.stderr").read_text()
        expected = "site_setting_extension.rb:1143:7: warning[unsupported]: runtime-defined method not supported"
        assert expected in diagnostic, "settings declaration blocker changed; investigate full original declaration closure"
        self.evidence["settings_closure_experiment"] = {
            "returncode": code, "actual_getter_declaration": "lib/site_setting_extension.rb:1143",
            "diagnostic": "runtime-defined method: define_singleton_method with a name computed when it runs",
            "actual_declaration_diagnostic": next(line for line in diagnostic.splitlines() if expected in line),
            "complete_original_inputs": {item["source"]: item["sha256"] for item in manifest["files"]},
            "bytes": sum(item["bytes"] for item in manifest["files"]),
            "complete_code_files": len(settings_closure.CODE_INPUTS),
            "boot_inventory_only": manifest["boot_inventory_only"],
            "limitation": "bounded complete-file dependency diagnostic ONLY; original GlobalSetting configure/plugin registration/load_defaults and initializer refresh are inventoried, not executed; other unresolved settings dependencies remain; output never executed or accepted",
        }

    def emit_options(self):
        return []

    def validate_guardian(self, guardian):
        assert "SiteSetting.suppress_secured_categories_from_admin" in guardian

    def generate(self):
        app = self.path / "input"
        self.command("project-source", ["ruby", HERE / "tools/project_topic_query.rb", HERE / "source/discourse", app], timeout=30)
        schema = self.schema()
        _, fixture = source_fixture([r["column_name"] for r in self.schema_rows if r["table_name"] == "topics"], category_security=True)
        self.evidence["source_fixture"] = fixture
        (self.path / "fixture.json").write_text(json.dumps(fixture, indent=2) + "\n")
        source = "(" + fixture["sql"] + ") AS topics"
        consumer = '''# Synthetic TEST consumer of the original audited partial expression.
class SecurityProbe
  def self.relation
    query = TopicQuery.new
    query.guardian = Guardian.new
    query.default_results
  end
  def self.fixture_relation
    relation.from(%s).order("topics.id ASC")
  end
  # Wrong TEST consumer only: omit category filtering, never edit Guardian.
  def self.wrong_scope_relation
    Topic.listable_topics.from(%s).order("topics.id ASC").includes(:category)
  end
end
''' % (json.dumps(source), json.dumps(source))
        for path, text in {
            "db/schema.rb": schema,
            "config/database.yml": "test:\n  adapter: postgresql\n  database: discourse_development\n",
            "config/routes.rb": "Rails.application.routes.draw do\nend\n",
            "app/controllers/application_controller.rb": "class ApplicationController < ActionController::Base\nend\n",
            "app/models/security_probe.rb": consumer,
        }.items():
            target = app / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.env.update(FIDELITY_SECURITY_CONSUMER=str(app / "app/models/security_probe.rb"),
                        FIDELITY_TOPIC_QUERY_EXPRESSION=str(app / "topic-query-expression.rb"),
                        FIDELITY_SECURITY_FIXTURE_FROM=source,
                        FIDELITY_EXTRA_ORIGINAL_INPUTS=json.dumps([
                            "lib/topic_query.rb", "lib/guardian.rb", "lib/guardian/topic_guardian.rb", "lib/guardian/category_guardian.rb",
                            "app/models/user.rb", "app/models/group.rb", "app/models/category_group.rb", "app/models/site_setting.rb",
                            "lib/site_setting_extension.rb", "lib/site_settings/db_provider.rb",
                            "lib/site_settings/yaml_loader.rb", "lib/site_settings/defaults_provider.rb", "lib/site_settings/type_supervisor.rb",
                            "app/models/site.rb", "app/models/theme.rb", "lib/cache.rb", "lib/discourse_redis.rb"]))
        self.command("roundhouse-build", ["cargo", "build", "--release", "--bin", "roundhouse"], cwd=ROOT / "roundhouse")
        self.command("emit", [ROOT / "roundhouse/target/release/roundhouse", "--target", "spinel", *self.emit_options(), app, "-o", self.path / "emitted"])
        emitted = self.path / "emitted"
        guardian = (emitted / "app/models/topic_guardian.rb").read_text()
        self.validate_guardian(guardian)
        assert '.references(:categories)' in guardian
        query = (emitted / "app/models/topic_query.rb").read_text()
        assert 'category_id_column: "categories.id"' in query and "result.merge(all_listable_topics)" in query
        self.evidence["projection_map"] = "input/projection-map.json"
        self.evidence["expression_sha256"] = digest((app / "topic-query-expression.rb").read_bytes())
        self.evidence["transformations"] = [{
            "feature": "scope/Concern/attribute declaration macros and ordinary lowering",
            "source": "input/projection-map.json original spans",
            "reason": "existing Roundhouse declaration expansion; original selected method/expression bytes not edited",
            "generated": "emitted/app/models/{topic,guardian,category_guardian,topic_guardian,topic_query}.rb",
            "equivalence": "not established natively; actual settings declaration closure missing",
        }]
        self.evidence["unsupported_application_body_rewrites"] = []
        packaged = list(emitted.rglob("*.rb"))
        self.evidence["slice_size"] = {"packaged_ruby_files": len(packaged), "packaged_ruby_bytes": sum(p.stat().st_size for p in packaged)}
        self.measure_settings_closure(app)
        self.save()

    def run_partial(self):
        entry = ENTRY
        probe = (HERE / "test/topic_query_probe.rb").read_text()
        (self.path / "entry.rb").write_text(entry)
        (self.path / "probe.rb").write_text(probe)
        pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
        if not (pg_dir / "pg.rb").is_file():
            raise RuntimeError("set SPINEL_PG_DIR to an existing spinel-pg0.2.0 checkout")
        code, _ = self.command("native-compile", [ROOT / "spinel/spinel", "--rbs", self.path / "emitted", "-I", pg_dir,
                                                self.path / "entry.rb", "-o", self.path / "probe"], check=False)
        if code:
            stderr = (self.path / "native-compile.stderr").read_text()
            if "undefined method 'suppress_secured_categories_from_admin'" not in stderr:
                raise RuntimeError("unexpected native failure; inspect native-compile.stderr")
            self.evidence["native_blocker"] = {
                "returncode": code, "diagnostic": "original TopicGuardian:273 references unexpanded SiteSetting.suppress_secured_categories_from_admin",
                "source_declaration": "app/models/site_setting.rb:83,109 extends original SiteSettingExtension and calls load_settings",
                "required_contract": "original YAML-driven class-declaration macro, define_singleton_method capture, effective runtime settings/default/provider/cache/plugin path; not a canned getter",
                "native_original_result": False, "native_elf_pg_trace": None,
            }
        else:
            # A future implementation must add full native execution/trace and
            # all required branches, not inherit a successful partial result.
            raise RuntimeError("native now compiles: extend this gate with ELF->PG execution and full security matrix before acceptance")
        compat = self.path / "compat"
        shutil.copytree(self.path / "emitted", compat / "emitted")
        shutil.copyfile(self.path / "entry.rb", compat / "entry.rb")
        shutil.copyfile(self.path / "probe.rb", compat / "probe.rb")
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        hashes = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
        compat_hashes = {str(p.relative_to(compat / "emitted")): digest(p.read_bytes()) for p in (compat / "emitted").rglob("*.rb")}
        differences = [p for p in hashes if hashes[p] != compat_hashes[p]]
        assert differences == ["runtime/pg_driver.rb"], differences
        self.evidence["same_lowered_ruby"] = {"hashes": hashes, "platform_only_difference": differences,
            "entry_sha256": digest(entry.encode()), "probe_sha256": digest(probe.encode()),
            "limitation": "identical inputs attempted, NOT native execution: compile refused"}
        self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
        self.env["FIDELITY_NEGATIVE_SCOPE"] = "1"
        try:
            self.command("compat-wrong-scope", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
        finally:
            del self.env["FIDELITY_NEGATIVE_SCOPE"]
        rows = self.records("compat")
        assert any(row.get("kind") == "row" for row in rows)
        assert [r["id"] for r in rows if r.get("kind") == "fixture"] == self.evidence["source_fixture"]["expected_ids"]
        assert [r["id"] for r in self.records("compat-wrong-scope") if r.get("kind") == "fixture"] == self.evidence["source_fixture"]["wrong_scope_expected_ids"]
        wrong = json.loads(json.dumps(rows))
        next(row for row in wrong if row.get("kind") == "row")["visible"] = 1
        try:
            equal_records(rows, wrong)
        except AssertionError:
            self.evidence["type_negative_control"] = True
        else:
            raise AssertionError("type control not detected")
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", HERE / "tools/topic_query_oracle_consumer.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        compat = self.records("compat")
        try:
            equal_records(compat, oracle)
            compat_equal = True
        except AssertionError:
            compat_equal = False
            differences = []
            for index in range(max(len(compat), len(oracle))):
                left = compat[index] if index < len(compat) else None
                right = oracle[index] if index < len(oracle) else None
                try:
                    equal_records([left], [right])
                except AssertionError:
                    differences.append({"index": index, "compat": left, "rails": right})
            self.evidence["strict_parity_failure"] = {"differences": differences,
                "contract": "derived NULL in a physically NOT NULL boolean column must not hydrate as false",
                "owner": "roundhouse/src/lower/model_to_library/row.rs from_raw / schema slot nilability",
                "accepted": False}
        # Isolate the category control from the separately recorded NULL/type
        # mismatch: compare real executed ID sets, not a comparator failure that
        # could have been caused solely by the pre-existing baseline difference.
        actual_ids = [row["id"] for row in oracle if row.get("kind") == "fixture"]
        compat_ids = [row["id"] for row in compat if row.get("kind") == "fixture"]
        wrong_ids = [row["id"] for row in self.records("compat-wrong-scope") if row.get("kind") == "fixture"]
        assert actual_ids == compat_ids == self.evidence["source_fixture"]["expected_ids"]
        assert wrong_ids == self.evidence["source_fixture"]["wrong_scope_expected_ids"]
        try:
            equal_records(actual_ids, wrong_ids)
        except AssertionError:
            self.evidence["category_negative_control"] = "actual CRuby ID-list query omitting category filtering leaks restricted derived case111; rejected against Rails ID list; NOT a native control"
        else:
            raise AssertionError("missing category filter not detected")
        if compat_equal:
            try:
                equal_records(self.records("compat-wrong-scope"), oracle)
            except AssertionError:
                self.evidence["category_strict_negative_control"] = "actual wrong-consumer CRuby records rejected against a strictly matching original Rails baseline; native control still missing"
            else:
                raise AssertionError("strict category omission control not detected")
        metadata = [json.loads(line.removeprefix("FIDELITY_SECURITY_ORACLE ")) for line in (self.path / "rails-oracle.stdout").read_text().splitlines() if line.startswith("FIDELITY_SECURITY_ORACLE ")]
        assert len(metadata) == 1
        self.evidence["rails_only_security_branches"] = metadata[0]
        cold = [json.loads(line.removeprefix("FIDELITY_SETTINGS_COLD ")) for line in (self.path / "rails-oracle.stdout").read_text().splitlines() if line.startswith("FIDELITY_SETTINGS_COLD ")]
        assert len(cold) == 1 and cold[0]["getter_effect_count"] > 0
        assert "del" in cold[0]["commands"]
        self.evidence["original_cold_settings_getter"] = cold[0]
        if compat_equal:
            self.evidence["projected_null_parity"] = "fixed: derived case107 remains SQL NULL/nil in compatibility and actual Rails; no field/case/schema constraint weakened"
        return {"live_rows": sum(r.get("kind") == "row" for r in oracle),
                "derived_fixture_rows": sum(r.get("kind") == "fixture" for r in oracle),
                "compat_equal": compat_equal, "native_equal": False, "scope": "anonymous partial expression ONLY; native missing, admin/member Rails-only"}

    def oracle_equivalence(self):
        if self.evidence["rails_parity"]["compat_equal"]:
            return "CRuby matches actual Rails on live rows and category/NULL fixtures; native original path still refused; no native equivalence claim"
        return "CRuby/Rails strict parity FAILS; native refused; no complete equivalence claim"


def main():
    run = TopicQueryRun()
    try:
        run.provenance()
        run.generate()
        run.run_partial()
        run.oracle()
        run.provenance()
        assert run.evidence["oracle_cleanup_verified"]
        run.evidence["status"] = "blocked_incomplete_topic_query_proof"
        run.evidence["remaining_contracts"] = [
            "Original cold settings getter reaches original refresh/cache invalidation effects (actual Rails evidence recorded); current writable fixture authorization is oracle-only, not native",
            "Effective original settings declaration/provider/cache/plugin closure; no frozen setting or fake getter",
            "Original authenticated User/group/category associations and applicable after_initialize callbacks under native/compat",
            "Original native security expression, direct ELF->PG trace, all applicable identity/admin branches and native negative control",
            "Rails joined-row eager hydration (compat currently filters with join then batch preloads); broader merge semantics",
            "Remaining default_results/latest_results/create_list/list_latest, then serializers/controller/document/browser",
        ]
        run.save()
        assert run.evidence["rails_parity"]["compat_equal"], "strict compat/Rails comparison still fails"
        print(f"NOT PASSED: original native category-security closure is incomplete. Strict CRuby/Rails parity now holds; native settings declaration/effects remain unproved: {run.path}", file=sys.stderr)
        return 1
    except Exception as error:
        run.evidence.update(status="failed", error=str(error))
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
