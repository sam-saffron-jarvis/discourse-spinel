#!/usr/bin/env python3
"""Cumulative genuine list body continuation; explicitly not an HTML response/page."""
import json
import os
import shutil
from pathlib import Path
from probe_category_cache_stage import OriginalCacheStageRun, verify_cache, lifecycle
from probe_latest_html_stage import verify_stage
from verify import HERE, ROOT, digest

BODY_FILES = ("native_list_body.rb", "original_list_body_models.rb", "original_list_date.rb", "list_body_context.rb", "list_body_original_context.rb", "list_head_context.rb", "list_head_original_context.rb", "list_head_source.rb", "original_list_head_helpers.rb")

class ListBodyStageRun(OriginalCacheStageRun):
    expected_icon_entries = {"opengraph_image_url"}
    success_status = "PASS_SOURCE_LIST_BODY_AND_HEAD_BEFORE_LAYOUT_HELPERS"
    def verify_continuation(self):
        pass
    def __init__(self):
        super().__init__()
        self.evidence.update(stage=__doc__, completed_body=False, layout_rendered=False)

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("generate-list-body-stage", ["bundle", "exec", "ruby", HERE / "tools/generate_list_body_stage.rb", app, self.path], cwd=ROOT / "discourse")
        self.command("generate-list-head-stage", ["bundle", "exec", "ruby", HERE / "tools/generate_list_head_stage.rb", app, self.path], cwd=ROOT / "discourse")
        self.evidence["list_head_source"] = json.loads((self.path / "list-head-source-proof.json").read_text())
        self.evidence["list_body_source"] = json.loads((self.path / "list-body-source-proof.json").read_text())

    def generate(self):
        super().generate()
        resource = self.path / "input/config/list_date_names.json"
        target = self.path / "emitted/config/list_date_names.json"
        shutil.copyfile(resource, target)
        assert digest(target.read_bytes()) == self.evidence["list_body_source"]["date_names_resource"]["sha256"]
        for name in BODY_FILES:
            source = HERE / "test" / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        probe = self.path / "probe.rb"
        lines = probe.read_text().splitlines()
        probe.write_text("\n".join("CategoryCacheOutput.write(" + line.strip()[5:] + ")" if line.strip().startswith("puts ") else line for line in lines) + "\n")
        entry = self.path / "entry.rb"
        text = entry.read_text()
        text = text.replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "list_body_context"\nrequire_relative "list_head_context"\nCategoryCacheBootstrap.configure(')
        text = text.replace('\nrequire_relative "probe"', '\nListHeadImages.configure(settings_configuration)\nrequire_relative "probe"')
        entry.write_text(text)
        self.evidence["body_entry_sha256"] = digest(text.encode())

    def command(self, name, argv, **kwargs):
        if name.startswith("compat"):
            tree = self.path / ("compat-preflight" if name == "compat-preflight" else "compat")
            if tree.exists():
                for item in BODY_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        if name == "compat-original":
            entry = self.path / "compat/entry-original.rb"
            text = entry.read_text()
            text = text.replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "category_cache_original_context"\nrequire_relative "list_body_original_context"\nrequire_relative "list_head_original_context"\nCategoryCacheBootstrap.configure(')
            entry.write_text(text)
        return super().command(name, argv, **kwargs)

def execute(run):
    try:
        run.provenance()
        run.generate()
        run.command("native-compile", [ROOT / "spinel/spinel", "--jobs=4", "--int-overflow=promote", "--rbs", run.path / "emitted", "-I", Path.home() / ".cache/spin/packages/pg-0.2.0", run.path / "entry.rb", "-o", run.path / "probe"])
        run.command("native", ["strace", "-f", "-e", "trace=execve,connect", "-o", run.path / "native.trace", run.path / "probe"], timeout=120)
        compat = run.path / "compat"
        shutil.copytree(run.path / "emitted", compat / "emitted")
        for name in ("entry.rb", "probe.rb"):
            shutil.copyfile(run.path / name, compat / name)
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", compat / "emitted/runtime/pg_driver.rb")
        run.command("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", compat / "entry.rb"], timeout=120)
        verify_stage(run)
        verify_cache(run)
        body_controls = {}
        for fault, error in (("drop-rss", "list RSS head missing"), ("drop-metadata", "list metadata head missing"), ("missing-body-return", "layout executed before completed body")):
            run.env["FIDELITY_BODY_FAULT"] = fault
            for runtime, argv in (("native", [run.path / "probe"]), ("compat", ["bundle", "exec", "ruby", compat / "entry.rb"])):
                name = runtime + "-body-" + fault
                code, _ = run.command(name, argv, check=False, timeout=120)
                assert code != 0 and error in (run.path / (name + ".stderr")).read_text(), name
                lifecycle(run, name)
                assert run.evidence["owned_cache_cleanup"][name]
                body_controls[name] = {"returncode": code, "expected_error": error, "thread_cleanup": True, "fixture_cleanup": True}
        del run.env["FIDELITY_BODY_FAULT"]
        icons = [lifecycle(run, name)["icon_cache"] for name in ("native", "compat", "compat-original")]
        assert icons[0] == icons[1] == icons[2] and set(icons[0]) == run.expected_icon_entries
        run.verify_continuation()
        run.evidence.update(status=run.success_status, completed_body=True, full_template_executed=True,
            body_wrong_output_controls=body_controls, acquired_icon_values=icons[0], html200_accepted=False, page_accepted=False)
    except BaseException as error:
        run.evidence.update(status="FAILED_LIST_BODY_CONTINUATION", error=repr(error))
        raise
    finally:
        run.save()
        print(run.path)

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ListBodyStageRun())

if __name__ == "__main__":
    main()
