#!/usr/bin/env python3
"""Fresh isolated-source probe. A blocked oracle is a failing gate, never a pass.

No Rails process or oracle file is a runtime dependency of the native ELF.
All private data, generated projections, logs and failed attempts stay in build/.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from source_fixture import source_fixture
from oracle_sandbox import ValkeySandbox

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def equal_records(left: list, right: list) -> None:
    # Python otherwise considers True == 1. Types are part of the contract.
    def typed(value):
        if isinstance(value, dict):
            return ("object", sorted((k, typed(v)) for k, v in value.items()))
        if isinstance(value, list):
            return ("array", [typed(v) for v in value])
        return (type(value).__name__, value)
    if typed(left) != typed(right):
        raise AssertionError("scope/query/type result mismatch")


class Run:
    def __init__(self, prefix="verify"):
        self.path = HERE / "build" / time.strftime(prefix + "-%Y%m%d-%H%M%S")
        self.path.mkdir(parents=True, exist_ok=False)
        self.env = os.environ.copy()
        self.env.update(CARGO_BUILD_JOBS="8", BUNDLE_JOBS="8", DATABASE_READONLY="1")
        self.env.update(DATABASE_URL="postgres://discourse@127.0.0.1:5499/discourse_development",
                        PGHOST="127.0.0.1", PGPORT="5499", PGUSER="discourse",
                        PGDATABASE="discourse_development", DATABASE_POOL_SIZE="2",
                        PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=15000",
                        REDIS_URL="redis://127.0.0.1:6399/0",
                        DISCOURSE_REDIS_HOST="127.0.0.1", DISCOURSE_REDIS_PORT="6399",
                        RAILS_ENV="development", BUNDLE_GEMFILE=str(ROOT / "discourse/Gemfile"),
                        FIDELITY_BARRIER_FILE=str(self.path / "oracle-barriers.jsonl"))
        self.evidence = {"stage": "isolated declaration slice, NOT full-model boot or TopicQuery",
                         "status": "in_progress", "commands": [], "source_revision": PIN}

    def save(self):
        (self.path / "evidence.json").write_text(json.dumps(self.evidence, indent=2) + "\n")

    def command(self, name, argv, cwd=ROOT, timeout=600, check=True):
        start = time.monotonic()
        with (self.path / f"{name}.stdout").open("wb") as out, (self.path / f"{name}.stderr").open("wb") as err:
            process = subprocess.Popen([str(a) for a in argv], cwd=cwd, env=self.env,
                                       stdout=out, stderr=err, start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                code = 124
            except BaseException:
                # This session/group was created by this exact Popen, not a
                # service discovered by name. Also clean it up on interruption.
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise
        self.evidence["commands"].append({"name": name, "argv": [str(a) for a in argv],
                                          "cwd": str(cwd), "seconds": round(time.monotonic() - start, 3),
                                          "returncode": code})
        self.save()
        if check and code:
            raise RuntimeError(f"{name} failed ({code}); see {self.path / (name + '.stderr')}")
        return code, (self.path / f"{name}.stdout").read_text()

    def provenance(self):
        lock = json.loads((HERE / "SOURCE_LOCK.json").read_text())
        assert lock["discourse_revision"] == PIN
        sources = {}
        for item in lock["files"]:
            upstream = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{PIN}:{item['path']}"])
            copied = (HERE / "source/discourse" / item["path"]).read_bytes()
            checked_out = (ROOT / "discourse" / item["path"]).read_bytes()
            assert upstream == copied == checked_out, item["path"]
            assert digest(upstream) == item["sha256"], item["path"]
            sources[item["path"]] = item["sha256"]
        assert subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "rev-parse", "HEAD"], text=True).strip() == PIN
        assert not subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "status", "--porcelain", "--untracked-files=no"], text=True)
        self.evidence["source_hashes"] = sources
        # Attest the actual read-only worker's original start, not its mutable
        # process title. These bytes are checked against the immutable pin;
        # they are not copied PG state or a new worker permission.
        vips_sources = {}
        for path in ("lib/discourse_vips.rb", "lib/discourse_vips/worker_process.rb", "script/discourse_vips_worker"):
            upstream = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{PIN}:{path}"])
            assert (ROOT / "discourse" / path).read_bytes() == upstream
            vips_sources[path] = digest(upstream)
        self.env["FIDELITY_VIPS_ORIGINAL_SOURCE_HASHES"] = json.dumps(vips_sources)
        self.evidence["original_vips_source_hashes"] = vips_sources
        from framework_sources import verify_framework_sources
        self.evidence["framework_sources"] = verify_framework_sources(lock, HERE, ROOT, digest)
        self.evidence["revisions"] = {repo: subprocess.check_output(["git", "-C", str(ROOT / repo), "rev-parse", "HEAD"], text=True).strip()
                                      for repo in ("roundhouse", "spinel", "fidelity")}
        compiler = ROOT / "spinel/spinel"
        version = subprocess.check_output([str(compiler), "--version"], text=True).strip()
        assert self.evidence["revisions"]["spinel"][:9] in version, "compiler build revision differs from recorded source; rebuild before proof"
        self.evidence["spinel_compiler"] = {"path": str(compiler.resolve()), "sha256": digest(compiler.read_bytes()),
                                            "version": version, "source_revision": self.evidence["revisions"]["spinel"]}
        self.save()

    def schema(self):
        # Pure PG catalog SELECT, NOT booting Rails or generating schema on DB.
        script = '''require "pg"; require "json"
c = PG.connect(ENV.fetch("DATABASE_URL"))
raise "writable catalog session" unless c.exec("SHOW default_transaction_read_only").getvalue(0,0) == "on"
puts JSON.generate(c.exec("SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('topics','categories') ORDER BY table_name,ordinal_position").to_a)
c.close
'''
        _, output = self.command("catalog", ["bundle", "exec", "ruby", "-e", script], cwd=ROOT / "discourse", timeout=60)
        rows = json.loads(output)
        assert len(rows) > 0
        (self.path / "schema.json").write_text(json.dumps(rows, indent=2) + "\n")
        types = {"integer": "integer", "bigint": "bigint", "character varying": "string", "text": "text",
                 "double precision": "float", "timestamp without time zone": "datetime", "boolean": "boolean"}
        lines = ["ActiveRecord::Schema.define do"]
        for table in ("topics", "categories"):
            columns = [r for r in rows if r["table_name"] == table]
            assert columns and columns[0]["column_name"] == "id" and columns[0]["data_type"] == "integer"
            lines.append(f'  create_table "{table}", id: :integer do |t|')
            for col in columns[1:]:
                # Defaults are intentionally not synthesized: this is a READ
                # probe, not proof of new/create/write semantics.
                lines.append(f'    t.{types[col["data_type"]]} "{col["column_name"]}", null: {str(col["is_nullable"] == "YES").lower()}')
            lines.append("  end")
        lines.append("end")
        self.evidence["schema"] = {"sha256": digest(json.dumps(rows, sort_keys=True).encode()),
                                   "columns": len(rows), "limitation": "Read-only column/type/null metadata; no DDL executed; defaults not tested"}
        self.schema_rows = rows
        return "\n".join(lines) + "\n"

    def generate(self):
        app = self.path / "input"
        self.command("project-source", ["ruby", HERE / "tools/project_source.rb", HERE / "source/discourse", app], timeout=30)
        schema = self.schema()
        methods, fixture = source_fixture([r["column_name"] for r in self.schema_rows if r["table_name"] == "topics"])
        self.evidence["source_fixture"] = fixture
        (self.path / "fixture.json").write_text(json.dumps(fixture, indent=2) + "\n")
        for path, text in {
            "db/schema.rb": schema,
            "config/database.yml": "test:\n  adapter: postgresql\n  database: discourse_development\n",
            "config/routes.rb": "Rails.application.routes.draw do\nend\n",
            "app/controllers/application_controller.rb": "class ApplicationController < ActionController::Base\nend\n",
            "app/models/scope_probe.rb": '''# frozen_string_literal: true
# Synthetic TEST consumer, not a replacement for any Discourse method.
class ScopeProbe
  def self.relation
    Topic.listable_topics.visible.where("topics.id >= ?", 0).order("topics.id ASC").limit(5).includes(:category)
  end
''' + methods + "end\n",
        }.items():
            target = app / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.command("roundhouse-build", ["cargo", "build", "--release", "--bin", "roundhouse"], cwd=ROOT / "roundhouse")
        self.command("emit", [ROOT / "roundhouse/target/release/roundhouse", "--target", "spinel", app, "-o", self.path / "emitted"])
        topic = (self.path / "emitted/app/models/topic.rb").read_text()
        assert '__rel.where.not(topics: { archetype: Archetype.private_message })' in topic
        assert '__rel.where(visible: true)' in topic
        assert '{ deleted_at: nil }' in topic
        assert 'def self._preload_batch_category' in topic
        for line in (371, 375):
            assert f'app/models/topic.rb:{line}' in topic
        self.evidence["transformations"] = [
            {"feature": "scope DSL lambda macro", "source": "app/models/topic.rb:371,375", "generated": "emitted/app/models/topic.rb:listable_topics,visible", "reason": "Existing Roundhouse static AR scope expansion; original lambda bodies copied into Relation-taking class methods", "equivalence": "native vs compat below; actual full Rails oracle required and may block"},
            {"feature": "Concern included default_scope macro", "source": "app/models/concerns/trashable.rb:7", "generated": "emitted/app/models/topic.rb:_default_scope_where", "reason": "Existing static default-scope metadata lowering", "equivalence": "generated SQL must retain deleted_at IS NULL; full Rails oracle required"},
        ]
        self.evidence["unsupported_application_body_rewrites"] = []
        self.evidence["projection_map"] = "input/projection-map.json"
        packaged = list((self.path / "emitted").rglob("*.rb"))
        self.evidence["slice_size"] = {"packaged_ruby_files": len(packaged),
                                        "packaged_ruby_bytes": sum(p.stat().st_size for p in packaged),
                                        "note": "Packaged output, not a claim that full Discourse model boot is reachable"}
        self.save()

    def run_partial(self):
        entry = '''# frozen_string_literal: true
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
# All physical pool paths must be read-only BEFORE the first application query.
2.times do |i|
  state = Db.pool.conn(i).client.exec("SELECT current_database(), inet_server_port(), current_setting('default_transaction_read_only')")
  raise "unsafe PG pool endpoint" unless state.getvalue(0, 0) == "discourse_development" && state.getvalue(0, 1) == "5499"
  raise "writable PG pool path" unless state.getvalue(0, 2) == "on"
end
Db.exec("BEGIN READ ONLY")
require_relative "probe"
Db.exec("ROLLBACK")
Db.close
'''
        probe = (HERE / "test/probe.rb").read_text()
        (self.path / "entry.rb").write_text(entry)
        (self.path / "probe.rb").write_text(probe)
        pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
        if not (pg_dir / "pg.rb").is_file():
            raise RuntimeError("set SPINEL_PG_DIR to an existing spinel-pg 0.2.0 checkout")
        self.evidence["pg_driver_sha256"] = {str(p.relative_to(pg_dir)): digest(p.read_bytes()) for p in sorted(pg_dir.rglob("*.rb"))}
        self.command("native-compile", [ROOT / "spinel/spinel", "--rbs", self.path / "emitted", "-I", pg_dir,
                                          self.path / "entry.rb", "-o", self.path / "probe"])
        assert (self.path / "probe").read_bytes()[:4] == b"\x7fELF"
        self.evidence["native_elf_sha256"] = digest((self.path / "probe").read_bytes())
        self.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", self.path / "native.trace", self.path / "probe"], timeout=60)
        trace = (self.path / "native.trace").read_text()
        assert trace.count("execve(") == 1, "native spawned another process"
        assert "htons(5499)" in trace and 'inet_addr("127.0.0.1")' in trace
        self.evidence["native_execution_path"] = {"execve_count": 1, "task_pg_connected": True, "trace": "native.trace"}
        compat = self.path / "compat"
        shutil.copytree(self.path / "emitted", compat / "emitted")
        shutil.copyfile(self.path / "entry.rb", compat / "entry.rb")
        shutil.copyfile(self.path / "probe.rb", compat / "probe.rb")
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        native_files = {str(p.relative_to(self.path / "emitted")): digest(p.read_bytes()) for p in (self.path / "emitted").rglob("*.rb")}
        compat_files = {str(p.relative_to(compat / "emitted")): digest(p.read_bytes()) for p in (compat / "emitted").rglob("*.rb")}
        differences = [p for p in native_files if native_files[p] != compat_files[p]]
        assert differences == ["runtime/pg_driver.rb"], differences
        self.evidence["same_lowered_ruby"] = {"hashes": native_files, "platform_only_difference": differences,
                                              "entry_sha256": digest(entry.encode()), "probe_sha256": digest(probe.encode())}
        self.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=60)
        self.env["FIDELITY_NEGATIVE_SCOPE"] = "1"
        try:
            self.command("native-wrong-scope", [self.path / "probe"], timeout=60)
        finally:
            del self.env["FIDELITY_NEGATIVE_SCOPE"]
        native = self.records("native")
        compat_rows = self.records("compat")
        equal_records(native, compat_rows)
        assert len([r for r in native if r.get("kind") == "row"]) > 0
        fixture_rows = [r for r in native if r.get("kind") == "fixture"]
        assert [r["id"] for r in fixture_rows] == self.evidence["source_fixture"]["expected_ids"]
        assert [r["id"] for r in self.records("native-wrong-scope") if r.get("kind") == "fixture"] == self.evidence["source_fixture"]["wrong_scope_expected_ids"]
        assert next(r for r in fixture_rows if r["id"] == 108)["category_id"] is None
        assert next(r for r in fixture_rows if r["id"] == 109)["category_name"] is None
        nullable = next(r for r in fixture_rows if r["id"] == 110)
        assert nullable["score"] is None and nullable["excerpt"] is None and nullable["user_id"] is None
        assert all(r["created_at"] == "2024-02-03T04:05:06.123456Z" for r in fixture_rows)
        wrong_type = json.loads(json.dumps(native))
        row = next(r for r in wrong_type if r.get("kind") == "row")
        row["visible"] = 1
        try:
            equal_records(native, wrong_type)
        except AssertionError:
            self.evidence["partial_negative_control"] = "detected boolean->integer mismatch; NOT a Rails scope control"
        else:
            raise AssertionError("negative type control did not fail")
        self.evidence["partial_native_compat"] = {"equal": True, "live_rows": sum(r.get("kind") == "row" for r in native),
                                                  "limitation": "Awaiting real Rails comparison; this phase is only native/compat evidence over live rows and derived fixtures"}
        self.save()

    def records(self, name):
        return [json.loads(line.removeprefix("FIDELITY ")) for line in (self.path / f"{name}.stdout").read_text().splitlines() if line.startswith("FIDELITY ")]

    def oracle_arguments(self):
        return [HERE / "tools/oracle.rb", self.path / "input/app/models/scope_probe.rb", self.path / "probe.rb"]

    def compare_oracle(self, oracle):
        equal_records(self.records("native"), oracle)
        equal_records(self.records("compat"), oracle)
        try:
            equal_records(self.records("native-wrong-scope"), oracle)
        except AssertionError:
            self.evidence["scope_negative_control"] = "actual native query omitting original visible scope rejected against full Rails oracle"
        else:
            raise AssertionError("actual wrong-scope execution was not detected")
        return {"live_rows": sum(r.get("kind") == "row" for r in oracle),
                "derived_fixture_rows": sum(r.get("kind") == "fixture" for r in oracle),
                "compat_equal": True, "native_equal": True,
                "scope": "isolated original declaration slice, NOT full-model native boot or TopicQuery"}

    def oracle_equivalence(self):
        return "native/compat match actual full Rails oracle on nonempty live rows and source-labelled SELECT-only negative fixtures"

    def oracle_application_root(self):
        # Historical proof profiles always use the immutable reference checkout.
        # Separately labelled patched profiles may override this location; the
        # complete-original-file byte checks below remain mandatory.
        return ROOT / "discourse"

    def oracle(self):
        authorization = (ROOT / "run/ORACLE_SANDBOX_AUTHORIZATION.json").read_bytes()
        policy = json.loads(authorization)
        assert "Valkey" in policy["scope"] and "disposable" in policy["scope"]
        self.evidence["oracle_sandbox_authorization_sha256"] = digest(authorization)
        # These negative controls run BEFORE any actual Rails boot. They prove
        # forbidden Redis/PG endpoints/options are rejected before dispatch,
        # and fixture lifecycle cleanup works on both success and exceptions.
        self.command("isolation-unit", ["bundle", "exec", "ruby", HERE / "test/oracle_isolation_test.rb"], cwd=ROOT / "discourse", timeout=60)
        self.command("sandbox-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test", "-p", "test_oracle_sandbox.py", "-v"], timeout=60)
        sandbox = ValkeySandbox(self.path / "oracle-fixture")
        try:
            with sandbox:
                self.evidence["oracle_sandbox_ready"] = json.loads(sandbox.evidence_path.read_text())
                self.save()
                self.env.update(sandbox.environment)
                self.env["FIDELITY_PG_CONNECTION_LOG"] = str(self.path / "oracle-pg-connections.jsonl")
                self.env["FIDELITY_VIPS_LOG"] = str(self.path / "oracle-readonly-vips.jsonl")
                self.env["FIDELITY_REJECTION_LOG"] = str(self.path / "oracle-policy-rejections.jsonl")
                self.env["FIDELITY_ORACLE_PHASE"] = "preflight"
                preflight = '''require ARGV.fetch(0)
port = Integer(ENV.fetch("FIDELITY_VALKEY_PORT"))
[6399, 5499, port == 6400 ? 6401 : 6400].each do |bad|
  begin
    Redis.new(host: "127.0.0.1", port: bad).ping
    raise "unsafe Redis endpoint was accepted"
  rescue FidelityOracleIsolation::UnsafeEndpoint
  end
end
begin
  Redis.new(path: "/tmp/fidelity-unowned.sock").ping
  raise "unowned socket accepted"
rescue FidelityOracleIsolation::UnsafeEndpoint
end
client = Redis.new(url: ENV.fetch("REDIS_URL"))
client.set("fidelity:preflight", "actual fixture effect")
raise "fixture effect not real" unless client.get("fidelity:preflight") == "actual fixture effect"
puts "private fixture writes real; shared and unknown endpoints rejected"
'''
                self.command("isolation-preflight", ["bundle", "exec", "ruby", "-e", preflight, HERE / "tools/oracle_isolation.rb"], cwd=ROOT / "discourse", timeout=30)
                self.env["FIDELITY_ORACLE_PHASE"] = "oracle"
                self.command("rails-oracle", ["bundle", "exec", "ruby", *self.oracle_arguments()],
                             cwd=ROOT / "discourse", timeout=120)
                rejections = [json.loads(line) for line in (self.path / "oracle-policy-rejections.jsonl").read_text().splitlines()]
                assert rejections and all(event["phase"] == "preflight" for event in rejections), "actual oracle attempted a forbidden endpoint/effect, even if rescued by the application"
                self.evidence["endpoint_rejection_control"] = {"before_boot": len(rejections), "actual_oracle_rejections": 0}
                oracle = self.records("rails-oracle")
                metadata = [json.loads(line.removeprefix("FIDELITY_ORACLE ")) for line in (self.path / "rails-oracle.stdout").read_text().splitlines() if line.startswith("FIDELITY_ORACLE ")]
                assert len(metadata) == 1
                for path, sha in metadata[0]["complete_original_files"].items():
                    assert self.evidence["source_hashes"][path] == sha
                assert metadata[0]["topic_slug_source"][0] == str(self.oracle_application_root() / "app/models/topic.rb")
                assert "/rack-mini-profiler-" in metadata[0]["pg_exec_source"][0], "enabled profiling hook was lost"
                self.evidence["actual_rails_oracle"] = metadata[0]
                assert oracle, "actual Rails oracle produced no results"
                pg_log = self.path / "oracle-pg-connections.jsonl"
                assert pg_log.exists() and pg_log.stat().st_size, "no guarded PG pool evidence"
                self.evidence["oracle_pg_connections"] = [json.loads(line) for line in pg_log.read_text().splitlines()]
                assert all(p["database"] == "discourse_development" and p["address"] == "127.0.0.1" and p["port"] == 5499 and p["default_transaction_read_only"] == "on" for p in self.evidence["oracle_pg_connections"])
                effects_log = Path(self.env["FIDELITY_VALKEY_WRITE_LOG"])
                effects = [json.loads(line) for line in effects_log.read_text().splitlines()]
                # Preflight alone is not proof that original boot effects ran.
                original_effects = [effect for effect in effects if effect.get("stage") == "successful_reply" and any("/discourse/" in frame for frame in effect.get("caller", []))]
                assert original_effects, "no real original Rails cache/logging effects captured"
                assert any(effect["command"] == "del" for effect in original_effects), "original cache invalidation did not execute"
                self.evidence["oracle_valkey_effects"] = {"count": len(effects), "original_effect_count": len(original_effects),
                                                          "successful_reply_observations": True,
                                                          "log": str(effects_log.relative_to(self.path))}
                vips_log = self.path / "oracle-readonly-vips.jsonl"
                if vips_log.exists():
                    helpers = [json.loads(line) for line in vips_log.read_text().splitlines()]
                    owned = {h["pid"] for h in helpers if h["stage"] == "owned_readonly_version"}
                    exited = {h["pid"] for h in helpers if h["stage"] == "owned_child_exited"}
                    assert owned and owned == exited, "original read-only Vips helper leaked"
                    self.evidence["original_readonly_helper"] = helpers
                stats = '''require ARGV.fetch(0)
r = Redis.new(url: ENV.fetch("REDIS_URL"))
raise "fixture preflight data disappeared" unless r.get("fidelity:preflight") == "actual fixture effect"
puts JSON.generate({info: r.info("stats"), keys: r.dbsize})
'''
                self.command("fixture-effects", ["bundle", "exec", "ruby", "-e", stats, HERE / "tools/oracle_isolation.rb"], cwd=ROOT / "discourse", timeout=30)
                # Preserve safety/effect evidence even when semantic parity
                # subsequently fails (e.g. missing real plugin activation).
                self.save()
                self.evidence["rails_parity"] = self.compare_oracle(oracle)
                for transform in self.evidence["transformations"]:
                    transform["equivalence"] = self.oracle_equivalence()
        finally:
            if sandbox.evidence_path.exists():
                self.evidence["oracle_sandbox"] = json.loads(sandbox.evidence_path.read_text())
                self.save()
        assert sandbox.cleanup_complete, "owned oracle fixture cleanup did not complete"
        self.evidence["oracle_cleanup_verified"] = True


def main():
    run = Run()
    try:
        run.provenance()
        run.generate()
        run.run_partial()
        run.oracle()
        run.provenance()
        assert run.evidence["oracle_cleanup_verified"]
        assert run.evidence["rails_parity"]["native_equal"] and run.evidence["rails_parity"]["compat_equal"]
        assert run.evidence["scope_negative_control"] and run.evidence["partial_negative_control"]
        run.evidence["status"] = "passed_isolated_original_scope"
        run.save()
        print(f"PASS: isolated original-scope AR/PG proof, NOT TopicQuery or /latest. Evidence: {run.path}")
        return 0
    except Exception as error:
        if run.evidence["status"] == "in_progress":
            run.evidence["status"] = "failed"
        run.evidence["error"] = str(error)
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
