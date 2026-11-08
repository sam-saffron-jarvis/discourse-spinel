#!/usr/bin/env python3
"""ONE new explicitly approved original Rails HTML experiment; never page acceptance."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time
from urllib.parse import urlencode

from oracle_sandbox import ValkeySandbox
from private_pg_fixture import AUTH, RESULT, USAGE, PrivatePG, approval, claim, update_usage
from probe_original_latest_html import audit_source
from verify import HERE, ROOT, Run, digest


def execute_child(argv, cwd, env, stdout, stderr, timeout):
    with stdout.open("wb") as out, stderr.open("wb") as err:
        process = subprocess.Popen([str(value) for value in argv], cwd=cwd, env=env, stdout=out, stderr=err,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
        return process


def wait_child(process, timeout):
    try:
        return process.wait(timeout=timeout)
    except BaseException:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        raise


def table_fingerprints(pg, name):
    # Hash inside PostgreSQL, never extract rows into diagnostic metadata.
    sql = """SELECT format('SELECT %L, count(*), md5(coalesce(string_agg(md5(row_to_json(t)::text), '''' ORDER BY md5(row_to_json(t)::text)), '''')) FROM %I.%I t;',
      tablename, schemaname, tablename) FROM pg_tables WHERE schemaname='public'
      AND tablename NOT IN ('site_settings','stylesheet_cache') ORDER BY tablename;
      \\gexec
    """
    output = pg.command(name, ["psql", "-XAt", "-v", "ON_ERROR_STOP=1"], pg.admin_env, input=sql)
    return digest(output.encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT / "fidelity/build/recovery24-frontend/source")
    args = parser.parse_args()
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    source = args.source_root.resolve()
    authorization_sha = approval()
    assert source == (ROOT / json.loads(AUTH.read_text())["source_root"]).resolve()
    assert source.is_relative_to((HERE / "build").resolve())
    run = Run("probe-private-original-html")
    run.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", LOAD_PLUGINS="0", LEFTHOOK="0")
    run.provenance()
    before_source = audit_source(source)
    # O_EXCL is the one-use claim. No dump, initdb, restore or Rails invocation
    # occurs until this succeeds, and no retry silently clears it.
    usage = claim(run.path, auth_sha=authorization_sha)
    result = {"status": "in_progress", "authorization_sha256": authorization_sha, "output": str(run.path),
              "original_source_before": before_source, "native_html_executed": False,
              "browser_rendered": False, "page_accepted": False, "old_approval_reused": False}
    pg = PrivatePG(run.path / "sensitive-pg-work", run.path, authorization_sha)
    cache = None
    code = 1
    source_log = source / "log/development.log"
    old_log_size = source_log.stat().st_size if source_log.exists() else None
    old_log_sha = digest(source_log.read_bytes()) if source_log.exists() else None
    try:
        with pg:
            fingerprint_before = table_fingerprints(pg, "unapproved-tables-before")
            work = pg.base
            cache = ValkeySandbox(work / "valkey", evidence_dir=work / "valkey")
            with cache:
                env = run.env | cache.environment
                for key in ("PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE", "PGPASSWORD", "PGPASSFILE"):
                    env.pop(key, None)
                env.update(PGHOST=str(pg.socket), PGPORT=str(pg.port), PGDATABASE="discourse_development", PGUSER="discourse",
                    PGOPTIONS="-c statement_timeout=15000 -c lock_timeout=5000",
                    DATABASE_URL="postgresql:///discourse_development?" + urlencode({"host": str(pg.socket), "port": pg.port, "user": "discourse"}),
                    DISCOURSE_DB_HOST=str(pg.socket), DISCOURSE_DB_PORT=str(pg.port), DISCOURSE_DB_USERNAME="discourse",
                    FIDELITY_PRIVATE_PG_MANIFEST=str(pg.manifest), FIDELITY_PRIVATE_PG_WRITE_LOG=str(run.path / "private-writes.jsonl"),
                    FIDELITY_PG_CONNECTION_LOG=str(run.path / "private-pools.jsonl"),
                    FIDELITY_REJECTION_LOG=str(work / "policy-rejections.private.jsonl"),
                    FIDELITY_VIPS_LOG=str(run.path / "readonly-vips.jsonl"),
                    FIDELITY_PRIVATE_HTML_OUTPUT=str(run.path), FIDELITY_VIPS_ORIGINAL_APPLICATION_ROOT=str(source))
                env["GIT_DIR"] = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "rev-parse", "--absolute-git-dir"], text=True).strip()
                env["GIT_WORK_TREE"] = str(source)
                usage["phase"] = "preflight"
                update_usage(usage)
                # Actual guard installed before any PG client. Wrong targets must
                # fail before dispatch; the one valid private connection is live-
                # checked as a child backend of our owned postmaster.
                preflight = r'''require ARGV.fetch(0)
[{host: "127.0.0.1", port: 5499}, {host: "127.0.0.1", port: 6399}, {host: "/tmp/unowned-private-pg"}, {dbname: "postgres"}, {user: "fixture_owner"}].each do |wrong|
  begin
    PG.connect({host: ENV.fetch("PGHOST"), port: ENV.fetch("PGPORT"), dbname: "discourse_development", user: "discourse"}.merge(wrong))
    raise "private PG guard accepted wrong endpoint"
  rescue FidelityOracleIsolation::UnsafeEndpoint
  end
end
c = PG.connect(host: ENV.fetch("PGHOST"), port: ENV.fetch("PGPORT"), dbname: "discourse_development", user: "discourse")
raise "wrong private backend" unless c.exec("SELECT current_database()").first["current_database"] == "discourse_development"
begin
  c.exec("INSERT INTO users(id) VALUES (-999)")
  raise "preflight allowed mutation"
rescue FidelityOracleIsolation::UnsafeEndpoint
end
c.close
puts "private endpoint/pool/write preflight passed"
'''
                process = execute_child(["bundle", "exec", "ruby", "-e", preflight, HERE / "tools/oracle_isolation.rb"], source, env,
                                        work / "preflight.stdout", work / "preflight.stderr", 45)
                if wait_child(process, 45):
                    raise RuntimeError("private PG guard preflight failed; no Rails experiment was run")
                result["live_endpoint_and_write_preflight_passed"] = True
                # Preserve prior genuine CSS artifacts, but execute cold original
                # cache compilation/writes in this authorized experiment.
                css = source / "tmp/stylesheet-cache"
                if css.exists():
                    shutil.move(str(css), str(run.path / "prior-generated-css"))
                usage.update(phase="rails_starting", rails_invocations=1)
                update_usage(usage)
                process = execute_child(["bundle", "exec", "ruby", HERE / "tools/private_html_reference_probe.rb"], source, env,
                                        work / "rails.stdout", work / "rails.stderr", 180)
                usage.update(phase="rails_running", rails_pid=process.pid)
                update_usage(usage)
                code = wait_child(process, 180)
                result["original_rails_returncode"] = code
                usage["phase"] = "rails_finished"
                update_usage(usage)
                # No raw Redis key/value or request diagnostic escapes the work
                # tree; retained evidence is just command counts and digests.
                writes = Path(env["FIDELITY_VALKEY_WRITE_LOG"])
                if writes.exists():
                    counts = Counter(json.loads(line)["command"] for line in writes.read_text().splitlines())
                    result["owned_valkey_effect_counts"] = dict(counts)
                barriers = Path(env["FIDELITY_REJECTION_LOG"])
                result["expected_guard_rejections"] = sum(1 for _ in barriers.open()) if barriers.exists() else 0
                result["raw_rails_stdout_sha256"] = digest((work / "rails.stdout").read_bytes())
                result["raw_rails_stderr_sha256"] = digest((work / "rails.stderr").read_bytes())
            result["owned_valkey_cleanup_verified"] = cache.cleanup_complete
            assert result["owned_valkey_cleanup_verified"]
            result["unapproved_tables_unchanged"] = table_fingerprints(pg, "unapproved-tables-after") == fingerprint_before
            assert result["unapproved_tables_unchanged"]
            if code == 0:
                reference = json.loads((run.path / "html-reference.json").read_text())
                effects = json.loads((run.path / "original-effects.json").read_text())
                assert len(reference["requests"]) == 2 and all(row["html_status"] == row["json_status"] == 200 and row["complete_topic_values_and_types_equal"] for row in reference["requests"])
                assert effects["wizard_false_to_true"] and effects["css_rows_added"] > 0
                result["original_html_200_and_paired_json_preloads_verified"] = True
                result["original_css_and_wizard_effects_verified"] = True
            result["status"] = "PASS_ORIGINAL_HTML_REFERENCE_ONLY" if code == 0 else "FAILED_ORIGINAL_HTML_REFERENCE"
    except BaseException as error:
        result.update(status="FAILED_ORIGINAL_HTML_REFERENCE", error_class=type(error).__name__,
                      error_message_sha256=digest(str(error).encode()))
        code = 1
    finally:
        result["private_pg"] = pg.record
        if cache is not None:
            result.setdefault("owned_valkey_cleanup_verified", cache.process is not None and
                              cache.process.poll() is not None and cache._cleanup_status == "child_exited")
        # Original logging ran; retain only a digest of this experiment's appended
        # log segment, restoring the earlier failure history byte-for-byte.
        if source_log.exists():
            data = source_log.read_bytes()
            if old_log_size is None:
                result["original_log_segment_sha256"] = digest(data)
                source_log.unlink()
            else:
                assert digest(data[:old_log_size]) == old_log_sha, "prior source log history changed"
                result["original_log_segment_sha256"] = digest(data[old_log_size:])
                with source_log.open("r+b") as stream:
                    stream.truncate(old_log_size)
        try:
            result["original_source_after"] = audit_source(source)
            result["original_source_unchanged"] = result["original_source_after"] == before_source
        except BaseException as error:
            result["original_source_unchanged"] = False
            result["source_audit_error_class"] = type(error).__name__
        result["authorization_consumed"] = True
        usage.update(status="consumed", phase="finished", result=str(RESULT), no_automatic_rerun=True,
                     cleanup_verified=pg.record["cleanup_verified"])
        update_usage(usage)
        if not pg.record["cleanup_verified"] or not result["original_source_unchanged"]:
            result["status"] = "FAILED_ISOLATION_OR_CLEANUP"
            code = 1
        text = json.dumps(result, indent=2) + "\n"
        (run.path / "result.json").write_text(text)
        with RESULT.open("x") as stream:
            stream.write(text)
        print(run.path)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
