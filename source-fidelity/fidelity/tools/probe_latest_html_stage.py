#!/usr/bin/env python3
"""Bounded HTML request/controller stage, never an original HTML oracle or HTML200."""
import json
import os
import shutil
import re
from pathlib import Path

from probe_latest_json_request import LatestJsonRequestRun
from verify import Run, HERE, ROOT, digest, equal_records


class LatestHtmlStageRun(LatestJsonRequestRun):
    def __init__(self):
        super().__init__()
        self.evidence.update(stage=__doc__, profile="readonly HTML controller through genuine derived list preload",
                             html200_accepted=False, native_html_accepted=False, original_html_accepted=False,
                             browser_accepted=False, page_accepted=False, broader019_accepted=False)

    def normalize_stage_record(self, row):
        return row

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("project-html-controller-stage", ["ruby", HERE / "tools/project_latest_html_stage.rb", app])
        self.evidence["html_stage_source"] = json.loads((app / "html-stage-source.json").read_text())

    def generate(self):
        super().generate()
        entry = self.path / "entry.rb"
        text = entry.read_text().replace('require_relative "latest_request_transport"', 'require_relative "latest_html_stage_transport"')
        ingress = HERE / "compat/framework/portable_html_stage_ingress.rb"
        text = 'require ' + json.dumps(str(ingress)) + '\nrequire ' + json.dumps(str(HERE / 'compat/discourse/lib/site_settings/portable_html_homepage_readers.rb')) + '\n' + text
        entry.write_text(text)
        self.env["FIDELITY_JSON_REQUEST_REFERENCE_DIRECTORY"] = str(self.path)
        shutil.copyfile(HERE / "test/latest_html_stage_transport.rb", self.path / "latest_html_stage_transport.rb")
        self.evidence["html_stage_transport_sha256"] = digest((self.path / "latest_html_stage_transport.rb").read_bytes())
        (self.path / "probe.rb").write_text('''# TEST caller, never fake Site/settings/preloader acquisition.
[["/latest", {"HTTP_ACCEPT" => "application/json"}],
 ["/latest", {"REQUEST_METHOD" => "POST"}],
 ["/latest", {"REMOTE_ADDR" => "192.0.2.1"}],
 ["/latest", {"HTTP_X_FORWARDED_FOR" => "127.0.0.1"}],
 ["/latest", {"HTTP_COOKIE" => "_t=unit-invalid"}],
 ["/latest", {"HTTP_HOST" => "attacker.invalid"}],
 ["/latest?format=json", {}]].each do |path, headers|
  begin
    LatestHtmlStageProbe.call(path, headers)
    raise "unsupported HTML stage ingress admitted"
  rescue ArgumentError => error
    raise unless error.message.include?("unsupported")
    raise "HTML ingress leaked context" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil? && Rack::MiniProfiler.current.nil? && I18n.locale == :fr
    puts "FIDELITY_HTML_INGRESS_CONTROL " + JSON.generate({refused: true, context_cleanup: true})
  end
end
["/latest", "/latest?per_page=2&page=1"].each do |path|
  puts "FIDELITY_HTML_STAGE " + JSON.generate(LatestHtmlStageProbe.call(path))
end
''')

    def command(self, name, argv, **kwargs):
        if name == "native-compile":
            if not (self.path / "compat-preflight.stdout").exists():
                self.compat_diagnostic()
            argv = list(argv)
            argv[1:1] = ["--timing", "--load-model=graph", "--no-inline-hot", "--cc=clang"]
            return Run.command(self, name, argv, timeout=600)
        if name == "compat-preflight":
            shutil.copyfile(self.path / "latest_html_stage_transport.rb", self.path / "compat-preflight/latest_html_stage_transport.rb")
        elif name == "compat":
            shutil.copyfile(self.path / "latest_html_stage_transport.rb", self.path / "compat/latest_html_stage_transport.rb")
        return super().command(name, argv, **kwargs)


def verify_stage(run):
    compat = run.path / "compat"
    rows = {}
    for name in ("native", "compat"):
        rows[name] = [json.loads(line.split(" ", 1)[1]) for line in (run.path / (name + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_HTML_STAGE ")]
        assert len(rows[name]) == 2
        for row in rows[name]:
            identifier = row.pop("request_id")
            assert re.fullmatch(r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}", identifier)
            assert row["refused"] is True and row["html200"] is False and row["site_acquired"] is False
            assert row["format"] == "html" and row["html_preload_marker"] is True
            run.normalize_stage_record(row)
    equal_records(rows["native"], rows["compat"])
    # Isolated ORIGINAL methods execute in a THIRD fresh CRuby process,
    # against freshly acquired store/rows; never invoke a Rails HTML oracle.
    original_methods = compat / "original_html_stage_methods.rb"
    run.command("generate-original-html-methods", ["ruby", HERE / "tools/generate_html_stage_original_methods.rb", original_methods])
    original_entry = compat / "entry-original.rb"
    text = (compat / "entry.rb").read_text()
    anchor = 'require_relative "latest_html_stage_transport"'
    assert text.count(anchor) == 1
    original_entry.write_text(text.replace(anchor, anchor + '\nrequire_relative "original_html_stage_methods"'))
    run.command("compat-original", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", original_entry], timeout=120)
    originals = [json.loads(line.split(" ", 1)[1]) for line in (run.path / "compat-original.stdout").read_text().splitlines() if line.startswith("FIDELITY_HTML_STAGE ")]
    assert len(originals) == 2
    for row in originals:
        assert all(row["original_methods"][name] is True for name in ("original_upcoming_and_defaults", "original_preload_marker", "original_constructor_and_storage"))
        row.pop("request_id")
        row["original_methods"] = None
        run.normalize_stage_record(row)
    equal_records(rows["native"], originals)
    controls = {}
    for fault, error in (("missing-marker", "HTML-specific preload marker missing"),
                         ("missing-storage", "HTML stage used fake Site data"),
                         ("duplicate-marker", "HTML callback/action order changed"),
                         ("wrong-theme", "HTML theme acquisition result changed")):
        run.env["FIDELITY_HTML_STAGE_FAULT"] = fault
        for runtime, argv in (("native", [run.path / "probe"]),
                              ("compat", ["bundle", "exec", "ruby", compat / "entry.rb"])):
            name = runtime + "-html-" + fault
            code, _ = run.command(name, argv, check=False, timeout=120)
            assert code != 0 and error in (run.path / (name + ".stderr")).read_text(), name
            assert run.evidence["owned_cache_cleanup"][name]
            controls[name] = {"returncode": code, "expected_error": error, "fixture_cleanup": True}
    del run.env["FIDELITY_HTML_STAGE_FAULT"]
    for runtime, argv in (("native", [run.path / "probe"]),
                          ("compat", ["bundle", "exec", "ruby", compat / "entry.rb"])):
        old_url = run.env["DATABASE_URL"]
        run.env["DATABASE_URL"] = "postgres://discourse@127.0.0.1:6399/discourse_development"
        try:
            name = runtime + "-html-wrong-endpoint"
            trace = run.path / (name + ".trace")
            code, _ = run.command(name, ["strace", "-f", "-e", "trace=connect", "-o", trace, *argv], check=False, timeout=30)
            assert code != 0 and "connect(" not in trace.read_text()
            assert "portable security PG endpoint guard" in (run.path / (name + ".stderr")).read_text()
            controls[name] = {"returncode": code, "connect_before_refusal": False}
        finally:
            run.env["DATABASE_URL"] = old_url
    for name in ("native", "compat", "compat-original"):
        ingress = [line for line in (run.path / (name + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_HTML_INGRESS_CONTROL ")]
        assert len(ingress) == 7 and all(json.loads(line.split(" ", 1)[1])["context_cleanup"] for line in ingress)
    native_files = {str(path.relative_to(run.path / "emitted")): digest(path.read_bytes()) for path in (run.path / "emitted").rglob("*.rb")}
    compat_files = {str(path.relative_to(compat / "emitted")): digest(path.read_bytes()) for path in (compat / "emitted").rglob("*.rb")}
    assert [path for path in native_files if native_files[path] != compat_files[path]] == ["runtime/pg_driver.rb"]
    sql_lines = [line.strip() for line in (run.path / "native.stderr").read_text().splitlines() if line.strip().startswith("SQL ")]
    assert any(line.startswith("SQL SELECT") and "FROM topics" in line for line in sql_lines)
    assert not any(re.match(r"SQL (?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE)\b", line, re.I) for line in sql_lines)
    run.evidence.update(same_lowered_ruby={"native_sha256": native_files, "only_platform_difference": "runtime/pg_driver.rb"},
                        native_observed_sql_count=len(sql_lines), ingress_controls_per_runtime=7,
                        built_csp_in_html_request=False, nonce_applied_in_html_request=False)
    run.evidence.update(status="PASS_PARTIAL_HTML_REQUEST_STAGE_NOT_HTML_RESPONSE", matched_stage_records=rows["native"],
        original_methods_proof=json.loads(Path(str(original_methods) + ".json").read_text()),
        security_order_controls=controls, original_html_request_invoked=False, original_isolated_methods_compared=True,
        html200_accepted=False, native_html_accepted=False, built_csp_in_html_request=False, nonce_applied_in_html_request=False, page_accepted=False)

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = LatestHtmlStageRun()
    try:
        run.provenance()
        run.generate()
        run.command("native-compile", [ROOT / "spinel/spinel", "--jobs=4", "--int-overflow=promote", "--rbs", run.path / "emitted",
            "-I", Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0"))), run.path / "entry.rb", "-o", run.path / "probe"], timeout=360)
        run.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", run.path / "native.trace", run.path / "probe"], timeout=120)
        compat = run.path / "compat"
        shutil.copytree(run.path / "emitted", compat / "emitted")
        for name in ("entry.rb", "probe.rb"):
            shutil.copyfile(run.path / name, compat / name)
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        run.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], cwd=ROOT / "discourse", timeout=120)
        verify_stage(run)
    except BaseException as error:
        run.evidence.update(status="FAILED_HTML_REQUEST_STAGE", error=repr(error))
        raise
    finally:
        run.save()
        print(run.path)


if __name__ == "__main__":
    main()
