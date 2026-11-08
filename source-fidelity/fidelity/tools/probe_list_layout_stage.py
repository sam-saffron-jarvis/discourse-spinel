#!/usr/bin/env python3
"""Actual application layout prefix after a complete list body, never a page."""
import json
import os
import shutil
from probe_list_body_stage import ListBodyStageRun, execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

LAYOUT_FILES = ("list_layout_source.rb", "native_list_layout.rb", "original_list_layout.rb", "list_layout_context.rb", "list_layout_original_context.rb", "list_color_source.rb", "original_list_color.rb", "list_color_context.rb", "list_color_original_context.rb", "original_list_canonical.rb")

class ListLayoutStageRun(ListBodyStageRun):
    additional_schema_tables = ("color_schemes", "color_scheme_colors")
    expected_icon_entries = {"opengraph_image_url", "favicon_url", "apple_touch_icon_url"}
    success_status = "PASS_SOURCE_LAYOUT_HEAD_COLOR_CACHE_PREFIX"

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("generate-list-layout-stage", ["bundle", "exec", "ruby", HERE / "tools/generate_list_layout_stage.rb", app, self.path], cwd=ROOT / "discourse")
        self.evidence["layout_source"] = json.loads((self.path / "list-layout-source-proof.json").read_text())

    def generate(self):
        super().generate()
        shutil.copyfile(self.path / "input/config/list_mime_types.json", self.path / "emitted/config/list_mime_types.json")
        target = self.path / "emitted/app/assets/stylesheets/common/foundation/colors.scss"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "discourse/app/assets/stylesheets/common/foundation/colors.scss", target)
        for name in LAYOUT_FILES:
            source = HERE / "test" / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        entry = self.path / "entry.rb"
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "list_layout_context"\nrequire_relative "list_color_context"\nCategoryCacheBootstrap.configure('))

    def verify_continuation(self):
        maps = [lifecycle(self, name)["color_cache"] for name in ("native", "compat", "compat-original")]
        assert maps[0] == maps[1] == maps[2] and maps[0]
        controls = {}
        for fault, expected in (("missing-color-publication", "missing category cache publication"),
                                ("color-job-exception", "negative layout color assignment exception"),
                                ("wrong-color-key", "category cache publication scope"),
                                ("drop-color-tags", "layout head omitted canonical/color metadata")):
            self.env["FIDELITY_LAYOUT_FAULT"] = fault
            for runtime, argv in (("native", [self.path / "probe"]), ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
                name = runtime + "-layout-" + fault
                code, _ = self.command(name, argv, check=False, timeout=120)
                error = (self.path / (name + ".stderr")).read_text()
                assert code != 0 and expected in error, (name, code, error[-1400:])
                lifecycle(self, name)
                assert self.evidence["owned_cache_cleanup"][name]
                controls[name] = {"returncode": code, "expected_error": expected, "thread_cleanup": True, "fixture_cleanup": True}
        del self.env["FIDELITY_LAYOUT_FAULT"]
        self.evidence.update(layout_prefix_executed=True, head_partial_completed=True, layout_completed=False,
            acquired_color_values=maps[0], layout_controls=controls)

    def command(self, name, argv, **kwargs):
        if name.startswith("compat"):
            tree = self.path / ("compat-preflight" if name == "compat-preflight" else "compat")
            if tree.exists():
                for item in LAYOUT_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        if name == "compat-original":
            entry = self.path / "compat/entry-original.rb"
            entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "list_layout_original_context"\nCategoryCacheBootstrap.configure('))
        return super().command(name, argv, **kwargs)

if __name__ == "__main__":
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ListLayoutStageRun())
