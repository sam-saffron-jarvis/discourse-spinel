#!/usr/bin/env python3
"""One execution trial of an already strictly emitted full latest candidate.

This is NOT Stage1/page acceptance. Compile, execution or parity failure exits
nonzero. It does not retry or expand the optional full-query source closure.
"""
import argparse
import json
import os
from pathlib import Path
import shutil

from probe_core_no_plugins import CoreNoPluginsRun
from probe_original_query import audit_projection
from compat_source_audit import audit
from verify import ROOT, HERE, digest, equal_records


class LatestExecutionRun(CoreNoPluginsRun):
    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/latest_method_reference_consumer.rb", self.path / "probe.rb"]


def observation(path):
    prefix = "FIDELITY_LATEST_EXECUTION "
    records = [json.loads(line[len(prefix):]) for line in path.read_text().splitlines() if line.startswith(prefix)]
    assert len(records) == 1, f"missing materialized query observation: {path}"
    return records[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="existing strict-RC0 portable full-query archive")
    args = parser.parse_args()
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    archive = args.archive.resolve()
    previous = json.loads((archive / "evidence.json").read_text())
    assert previous["strict_inventory"]["returncode"] == 0, "refused lowering output cannot execute"
    assert not previous["strict_inventory"]["diagnostics"]
    assert previous["compiler_sha256"] == digest((ROOT / "roundhouse/target/release/roundhouse").read_bytes())
    audit_projection(archive / "latest-method-input")
    audit(archive / "latest-method-input")
    run = LatestExecutionRun()
    run.evidence.update(stage="one guarded full-query execution trial; not cumulative Stage1 or page acceptance",
        strict_emit_ok=True, native_compile_ok=False, native_query_executed=False, stage_parity=False,
        complete_default_results_accepted=False, full_query_accepted=False, page_accepted=False,
        strict_archive=str(archive), candidate_manifest=json.loads((HERE / "compat/MANIFEST.json").read_text()))
    try:
        run.provenance()
        run.initial_reference()
        expected = observation(run.path / "rails-oracle.stdout")
        shutil.copytree(archive / "latest-method-emitted", run.path / "emitted")
        source = (archive / "native-latest-entry.rb").read_text()
        first = source.index("query = TopicQuery.new(nil, per_page: 20)")
        last = source.index('Db.exec("ROLLBACK")', first)
        observer = (HERE / "test/latest_execution_observer.rb").read_text()
        entry = source[:first] + observer + "\n" + source[last:]
        path = run.path / "entry.rb"
        path.write_text(entry)
        binary = run.path / "native-latest"
        pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
        run.evidence["pg_driver_sha256"] = {str(p.relative_to(pg_dir)): digest(p.read_bytes()) for p in sorted(pg_dir.rglob("*.rb"))}
        code, _ = run.command("native-compile", [ROOT / "spinel/bin/spinel", "--load-model=graph", "--no-inline-hot", "--cc=clang",
            "--jobs=4", "--rbs", run.path / "emitted", "-I", pg_dir, path, "-o", binary], check=False, timeout=360)
        assert code == 0, "full native compile failed; output NOT executed; next milestone is progressive Stage1"
        run.evidence["native_compile_ok"] = True
        assert binary.read_bytes()[:4] == b"\x7fELF"
        run.evidence["native_elf_sha256"] = digest(binary.read_bytes())
        compat = run.path / "compat"
        shutil.copytree(run.path / "emitted", compat / "emitted")
        shutil.copyfile(path, compat / "entry.rb")
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        native_hashes = {str(p.relative_to(run.path / "emitted")): digest(p.read_bytes()) for p in (run.path / "emitted").rglob("*.rb")}
        compat_hashes = {str(p.relative_to(compat / "emitted")): digest(p.read_bytes()) for p in (compat / "emitted").rglob("*.rb")}
        assert [name for name in native_hashes if native_hashes[name] != compat_hashes[name]] == ["runtime/pg_driver.rb"]
        run.evidence["same_lowered_ruby"] = {"hashes": native_hashes, "entry_sha256": digest(entry.encode()),
            "platform_only_difference": ["runtime/pg_driver.rb"]}
        original_url = run.env["DATABASE_URL"]
        run.env["DATABASE_URL"] = "postgres://discourse@127.0.0.1:6399/discourse_development"
        try:
            for runtime, command in (("native", [binary]), ("compat", ["bundle", "exec", "ruby", compat / "entry.rb"])):
                trace = run.path / (runtime + "-wrong-endpoint.trace")
                code, _ = run.command(runtime + "-wrong-endpoint", ["strace", "-f", "-e", "trace=connect", "-o", trace, *command], check=False, timeout=30)
                assert code != 0 and "portable latest endpoint guard" in (run.path / (runtime + "-wrong-endpoint.stderr")).read_text()
                assert "connect(" not in trace.read_text(), "wrong endpoint attempted a connection"
        finally:
            run.env["DATABASE_URL"] = original_url
        run.evidence["endpoint_negatives_before_connect"] = True
        trace = run.path / "native.trace"
        native_code, native_output = run.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary], check=False, timeout=60)
        run.evidence["native_query_executed"] = "FIDELITY_LATEST_QUERY_ENTER" in native_output
        compat_code, _ = run.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", check=False, timeout=60)
        trace_text = trace.read_text()
        assert trace_text.count("execve(") == 1, "native spawned a child"
        connections = [line for line in trace_text.splitlines() if "connect(" in line]
        assert all('htons(5499)' in line and 'inet_addr("127.0.0.1")' in line for line in connections), "unapproved native network endpoint"
        run.evidence["native_execution_path"] = {"execve_count": 1, "pg_connections": len(connections), "ruby_child": False}
        assert native_code == compat_code == 0, "full query runtime failed; retain boundary and progress from executable Stage1"
        assert connections, "successful query did not connect to PG"
        actual = observation(run.path / "native.stdout")
        equal_records(expected, actual)
        equal_records(expected, observation(run.path / "compat.stdout"))
        assert actual["rows"], "no materialized rows"
        wrong = json.loads(json.dumps(actual))
        wrong["rows"][0][0][0] = str(wrong["rows"][0][0][0])
        try:
            equal_records(expected, wrong)
        except AssertionError:
            run.evidence["wrong_type_rejected"] = True
        else:
            raise AssertionError("wrong materialized row type accepted")
        run.evidence.update(status="full_query_trial_four_fields_three_way_equal_ONLY", stage_parity=True,
            materialized_rows=actual["rows"], full_query_accepted=False)
        run.provenance()
    except BaseException as error:
        run.evidence.update(status="FAILED_full_query_execution_trial", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
