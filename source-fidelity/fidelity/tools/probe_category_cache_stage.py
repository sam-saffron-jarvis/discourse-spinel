#!/usr/bin/env python3
"""Category cache acquisition on the cumulative real HTML request path, NOT a page."""
import json
import os
import shutil
from pathlib import Path
from probe_list_template_stage import ListTemplateStageRun
from probe_latest_html_stage import verify_stage
from verify import HERE, ROOT, digest

CACHE_FILES = ("category_cache_subscriptions.rb", "original_category_cache_subscription.rb", "category_cache_bus_source.rb", "category_cache_application_source.rb",
    "original_category_cache_application_source.rb", "category_cache_single_site.rb",
    "category_cache_category_methods.rb", "native_category_cache_category_methods.rb", "category_cache_transport.rb", "category_cache_context.rb",
    "category_cache_original_context.rb")

class CategoryCacheStageRun(ListTemplateStageRun):
    def __init__(self):
        super().__init__()
        self.env["SPINEL_WORKERS"] = "4"
        self.evidence.update(stage=__doc__, cache_effect_classification=str(HERE / "RECOVERY31.md"),
            cache_capability_accepted=False, completed_body=False, layout_rendered=False)

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("generate-category-cache-source", ["bundle", "exec", "ruby", HERE / "tools/generate_category_cache_source.rb", self.path, app], cwd=ROOT / "discourse")
        self.evidence["category_cache_source_proof"] = json.loads((self.path / "category-cache-source-proof.json").read_text())

    def generate(self):
        super().generate()
        for name in CACHE_FILES:
            source = HERE / "test" / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        (self.path / "emitted/runtime/category_cache_acquisition.rbs").write_text("""module CategoryCacheBootstrap
  def self.cache: () -> ::CategoryCacheApplication::DistributedCache
  def self.body_icon_cache: () -> ::CategoryCacheApplication::DistributedCache
  def self.layout_color_cache: () -> ::CategoryCacheApplication::DistributedCache
  def self.theme_compiler_cache: () -> ::CategoryCacheApplication::DistributedCache
end
module CategoryCacheApplication
  class DistributedCache
    def defer_get_set: (String key) { () -> String } -> String
  end
end
""")
        prefix_context = self.path / "list_template_prefix_context.rb"
        original_prefix_context = prefix_context.read_text()
        assert original_prefix_context.count("  def observation\n") == 1
        prefix_context.write_text(original_prefix_context.replace("  def observation\n", "  def prefix_observation\n"))
        self.evidence["template_context_sha256"] = digest(prefix_context.read_bytes())
        transport = self.path / "latest_html_stage_transport.rb"
        forwarding = "\n".join(f"class {name}\n  def ensure_dont_cache_page\n    super\n  end\nend" for name in ("HtmlMissingMarkerController", "HtmlMissingStorageController", "HtmlDuplicateMarkerController", "HtmlWrongThemeController"))
        transport.write_text(transport.read_text() + "\n# Explicit inherited around-callback forwarding; no body/assertion changed.\n" + forwarding + "\n")
        self.evidence["html_stage_transport_sha256"] = digest(transport.read_bytes())
        entry = self.path / "entry.rb"
        text = entry.read_text()
        anchor = 'LatestRequestProbe.configure_profiler(cache_policy, cache_connection)'
        assert text.count(anchor) == 1
        namespace = self.evidence["request_cache_namespace_declaration"]["declaration"].split(" = ", 1)[1]
        setup = '\n'.join(f'require_relative "{name[:-3]}"' for name in ("category_cache_transport.rb", "category_cache_subscriptions.rb", "category_cache_context.rb", "category_cache_single_site.rb", "category_cache_bus_source.rb", "category_cache_application_source.rb", "native_category_cache_category_methods.rb"))
        text = text.replace(anchor, anchor + '\nbegin\n' + setup + f'\nCategoryCacheBootstrap.configure(settings_configuration, {namespace})')
        text = text.replace('require_relative "probe"', 'require_relative "probe"\nensure\nbegin\nCategoryCacheBootstrap.close!\nensure\ncache_connection.close\nend\nend')
        entry.write_text(text)
        self.evidence["cache_entry_sha256"] = digest(text.encode())

    def command(self, name, argv, **kwargs):
        if name.startswith("compat"):
            tree = self.path / ("compat-preflight" if name == "compat-preflight" else "compat")
            if tree.exists():
                for item in CACHE_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        if name == "compat-original":
            # Parent adds its original template context immediately after this
            # anchor. Our raw cache override must load AFTER that parent context.
            result = super().command(name, argv, **kwargs)
            return result
        return super().command(name, argv, **kwargs)

    def validate_native_cache_connections(self, trace, port):
        connections = [line for line in trace.splitlines() if "connect(" in line]
        assert trace.count("execve(") == 1
        assert len(connections) == 6, connections
        assert sum("htons(5499)" in line for line in connections) == 2
        assert sum(f"htons({port})" in line for line in connections) == 4
        assert all('inet_addr("127.0.0.1")' in line for line in connections)

# Inject the original cache dependency after the original template adapter without
# editing the preserved Recovery30 adapter or invoking Rails application boot.
class OriginalCacheStageRun(CategoryCacheStageRun):
    def command(self, name, argv, **kwargs):
        if name == "compat-original":
            entry = self.path / "compat/entry-original.rb"
            text = entry.read_text()
            text = text.replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "category_cache_original_context"\nCategoryCacheBootstrap.configure(')
            # The parent's insertion then puts list_template_original_context
            # before category_cache_original_context, as required.
            entry.write_text(text)
        return super().command(name, argv, **kwargs)

def lifecycle(run, name):
    records = [json.loads(line.split(" ", 1)[1]) for line in (run.path / (name + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_CATEGORY_CACHE_LIFECYCLE ")]
    assert len(records) == 1, name
    record = records[0]
    assert record["threads_after"] == record["threads_before"], (name, record)
    return record

def verify_cache(run):
    values = []
    for name in ("native", "compat", "compat-original"):
        record = lifecycle(run, name)
        assert record["ready"] and record["namespace"] == "default", (name, record)
        assert record["queued"] == record["finished"] and record["publications"] == record.get("expected_publications", record["queued"]) and record["publications"] > 0, (name, record)
        assert record["errors"] == 0 and record["pending"] == 0 and record["received_callbacks"] >= record["publications"], (name, record)
        assert record["cache"] == record["server_values"], (name, record)
        rows = [json.loads(line.split(" ", 1)[1]) for line in (run.path / (name + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_HTML_STAGE ")]
        expected = {}
        for row in rows:
            view = row["template_prefix"]
            if "category_urls" in view:
                expected.update(view["category_urls"])
            else:
                expected[str(view["category_id"])] = view["category_url"]
        assert record["cache"] == expected, (name, record, expected)
        values.append(record["cache"])
    assert values[0] == values[1] == values[2]
    controls = {}
    for fault, expected in (("shared-endpoint", "protected/unknown cache endpoint"),
            ("unknown-endpoint", "protected/unknown cache endpoint"),
            ("wrong-namespace", "category cache site namespace"),
            ("wrong-runtime", "category cache runtime ownership"),
            ("wrong-message-namespace", "category cache inbound namespace"),
            ("missing-subscription", "category cache subscription missing"),
            ("missing-publication", "missing category cache publication"),
            ("missing-defer", "category cache publication bypassed real defer"),
            ("wrong-update-order", "category cache publication/update order"),
            ("job-exception", "negative deferred assignment exception")):
        run.env["FIDELITY_CACHE_FAULT"] = fault
        for runtime, argv in (("native", [run.path / "probe"]), ("compat", ["bundle", "exec", "ruby", run.path / "compat/entry.rb"])):
            name = runtime + "-cache-" + fault
            trace = run.path / (name + ".trace")
            rc, _ = run.command(name, ["strace", "-f", "-e", "trace=connect", "-o", trace, *argv], check=False, timeout=60)
            error = (run.path / (name + ".stderr")).read_text()
            assert rc != 0 and expected in error, (name, rc, error[-1600:])
            record = lifecycle(run, name)
            assert run.evidence["owned_cache_cleanup"][name]
            port = run.evidence["owned_cache_runtime_effects"][name]["port"]
            connections = [line for line in trace.read_text().splitlines() if "connect(" in line]
            assert all('inet_addr("127.0.0.1")' in line and ("htons(5499)" in line or f"htons({port})" in line) for line in connections), (name, connections)
            controls[name] = {"returncode": rc, "expected_error": expected, "thread_cleanup": True, "fixture_cleanup": True}
    del run.env["FIDELITY_CACHE_FAULT"]
    run.evidence["cache_lifecycle_controls"] = controls
    run.evidence["cache_lifecycle_values"] = values[0]

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = OriginalCacheStageRun()
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
        run.evidence.update(status="PASS_SCOPED_CATEGORY_CACHE_REQUEST_ACQUISITION", cache_capability_accepted=True, html200_accepted=False, page_accepted=False)
    except BaseException as error:
        run.evidence.update(status="FAILED_CATEGORY_CACHE_ACQUISITION", error=repr(error))
        raise
    finally:
        run.save()
        print(run.path)

if __name__ == "__main__":
    main()
