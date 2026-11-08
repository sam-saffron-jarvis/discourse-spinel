#!/usr/bin/env python3
"""Actual source template prefix after genuine HTML controller, no page/effect dispatch."""
import json
import os
import shutil
from pathlib import Path
from probe_latest_html_stage import LatestHtmlStageRun, verify_stage
from verify import HERE, ROOT, digest

class ListTemplateStageRun(LatestHtmlStageRun):
    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("generate-list-template-prefix", ["bundle", "exec", "ruby", HERE / "tools/generate_list_template_prefix.rb", app, self.path], cwd=ROOT / "discourse")
        self.evidence["template_prefix_proof"] = json.loads((self.path / "template-prefix-proof.json").read_text())

    def generate(self):
        super().generate()
        proof = self.evidence["template_prefix_proof"]
        constants = "class TemplatePrefixSource\n" + "\n".join(f"{name} = {json.dumps(proof[key])}" for name, key in (("BODY_PATH","body_path"),("BODY_SHA",None),("LAYOUT_PATH","layout_path"),("LAYOUT_SHA","layout_sha256")) if key) + "\nBODY_SHA = " + json.dumps(proof["original_source_sha256"]["app/views/list/list.erb"]) + "\nend\n"
        context = self.path / "list_template_prefix_context.rb"
        context.write_text(constants + (HERE / "test/list_template_prefix_context.rb").read_text())
        shutil.copyfile(HERE / "test/list_template_original_context.rb", self.path / "list_template_original_context.rb")
        transport = self.path / "latest_html_stage_transport.rb"
        text = transport.read_text().replace('{original_methods: original, callback_order:', '{template_prefix: controller.instance_variable_get(:@template_prefix_context).observation, original_methods: original, callback_order:')
        transport.write_text(text + '\nrequire_relative "list_template_prefix_context"\n')
        self.evidence["html_stage_transport_sha256"] = digest(transport.read_bytes())
        self.evidence["template_context_sha256"] = digest(context.read_bytes())

    def command(self, name, argv, **kwargs):
        if name.startswith("compat"):
            tree = self.path / ("compat-preflight" if name == "compat-preflight" else "compat")
            if tree.exists():
                for item in ("list_body_prefix.rb", "source_renderer_sequence.rb", "list_template_prefix_context.rb",
                             "original_list_body.rb", "original_template_helpers.rb", "original_renderer_sequence.rb", "original_topic_urls.rb", "original_category_url.rb", "list_template_original_context.rb"):
                    shutil.copyfile(self.path / item, tree / item)
        if name == "compat-original":
            entry = self.path / "compat/entry-original.rb"
            entry.write_text(entry.read_text().replace('require_relative "original_html_stage_methods"', 'require_relative "original_html_stage_methods"\nrequire_relative "list_template_original_context"'))
        return super().command(name, argv, **kwargs)

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = ListTemplateStageRun()
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
        template_controls = {}
        for fault, message in (("drop-title", "genuine template title missing/escaping changed"), ("unescaped", "template accumulator failed escaping unit control"), ("layout-first", "layout executed before body refusal")):
            run.env["FIDELITY_TEMPLATE_FAULT"] = fault
            for runtime, argv in (("native", [run.path / "probe"]), ("compat", ["bundle", "exec", "ruby", compat / "entry.rb"])):
                name = runtime + "-template-" + fault
                code, _ = run.command(name, argv, check=False, timeout=120)
                assert code != 0 and message in (run.path / (name + ".stderr")).read_text(), name
                assert run.evidence["owned_cache_cleanup"][name]
                template_controls[name] = {"returncode": code, "expected_error": message, "owned_fixture_cleanup": True}
        del run.env["FIDELITY_TEMPLATE_FAULT"]
        run.evidence.update(status="PASS_SOURCE_LIST_TEMPLATE_PREFIX_BEFORE_CACHE_CAPABILITY", template_wrong_output_controls=template_controls, full_template_rendered=False, layout_rendered=False,
                            original_rails_html_invoked=False, html200_accepted=False, page_accepted=False)
    except BaseException as error:
        run.evidence.update(status="FAILED_TEMPLATE_PREFIX", error=repr(error))
        raise
    finally:
        run.save()
        print(run.path)
if __name__ == "__main__":
    main()
