#!/usr/bin/env python3
"""Experimental typed Theme Array cache; never accepts a page or unauthorized bake."""
import json
import os
import shutil
from probe_importmap_compiler_stage import ImportMapCompilerStageRun
from probe_list_layout_stage import ListLayoutStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

ARRAY_FILES = ("native_theme_array_context.rb", "original_theme_array_context.rb", "theme_array_transport.rb")

class ThemeArrayStageRun(ImportMapCompilerStageRun):
    additional_schema_tables = ImportMapCompilerStageRun.additional_schema_tables + ("theme_fields", "javascript_caches")
    success_status = "PASS_SCOPED_THEME_ARRAY_CACHE_BEFORE_ASSET_GRAPH"
    allow_array_cache = True

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("generate-theme-array-capability", ["bundle", "exec", "ruby", HERE / "tools/generate_theme_array_capability.rb", app, self.path], cwd=ROOT / "discourse")
        self.evidence["theme_array_source"] = json.loads((self.path / "theme-array-source-proof.json").read_text())

    def generate(self):
        super().generate()
        (self.path / "emitted/runtime/theme_array.rbs").write_text('''module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_assets: (String key) { () -> Array[Hash[Symbol, String | Integer | Array[String]]] } -> Array[Hash[Symbol, String | Integer | Array[String]]]
  end
end
module ListThemeCompilerSource
  def self.get_set_cache_assets: (String key) { () -> Array[Hash[Symbol, String | Integer | Array[String]]] } -> Array[Hash[Symbol, String | Integer | Array[String]]]
end
''')
        bus_source = self.path / "category_cache_bus_source.rb"
        text = bus_source.read_text()
        anchor = 'value = Base64.encode64(Marshal.dump(value)) if marshal'
        assert text.count(anchor) == 1
        text = text.replace(anchor, anchor + '\n        value = value + "tampered" if marshal && ENV.fetch("FIDELITY_ARRAY_FAULT", "") == "wrong-wire"\n        marshal = false if marshal && ENV.fetch("FIDELITY_ARRAY_FAULT", "") == "wrong-marshal-flag"\n        return if ENV.fetch("FIDELITY_ARRAY_FAULT", "") == "missing-array-publication" && key.include?(":extra_js:")')
        bus_source.write_text(text)
        transport = (self.path / "category_cache_transport.rb").read_text()
        transport = transport.replace('data["marshalled"] == false', 'admitted_value?(data)')
        transport = transport.replace('key == "compiler_version"', 'key == "compiler_version" || (!@theme_array_encodings.nil? && @theme_array_encodings.key?(key))')
        (self.path / "category_cache_transport.rb").write_text(transport)
        (self.path / "theme_array_transport.rb").write_text('''class CategoryCacheLease
  def note_theme_array(key, value)
    raise "unadmitted Theme array key" unless /\\A[-0-9,]+:extra_js:[a-f0-9]{40}\\z/.match?(key)
    raise TypeError, "Theme asset result is not Array" unless value.is_a?(Array)
    value.each do |row|
      raise TypeError, "Theme asset record shape" unless row.is_a?(Hash) && row.keys.sort == [:external_plugin_imports, :theme_id, :url] && row[:url].is_a?(String) && row[:theme_id].is_a?(Integer) && row[:external_plugin_imports].is_a?(Array) && row[:external_plugin_imports].all? { |x| x.is_a?(String) }
    end
    @theme_array_encodings ||= {}
    @theme_array_encodings[key] = Base64.encode64(Marshal.dump(value))
  end
  def admitted_value?(data)
    if data["hash_key"] == theme_cache_key && !@theme_array_encodings.nil? && @theme_array_encodings.key?(data["key"])
      data["marshalled"] == true && @theme_array_encodings[data["key"]] == data["value"]
    else
      data["marshalled"] == false && data["value"].is_a?(String)
    end
  end
  def decoded_theme_value(data)
    raise "unowned encoded Theme value" unless admitted_value?(data)
    data["marshalled"] ? Marshal.load(Base64.decode64(data["value"])) : data["value"]
  end
end
''')
        context = self.path / "category_cache_context.rb"
        text = context.read_text().replace('data["marshalled"] == false', '(data["marshalled"] == false || data["hash_key"] == lease.theme_cache_key)')
        text = text.replace('server_theme_compiler_values[data["key"]] = data["value"]', 'server_theme_compiler_values[data["key"]] = lease.decoded_theme_value(data)')
        text = text.replace('hit = acquired_theme_compiler_cache.defer_get_set(key) { raise "genuine compiler version hit recomputed" }', 'hit = value.is_a?(Array) ? acquired_theme_compiler_cache.defer_get_set_assets(key) { raise "genuine Theme Array hit recomputed" } : acquired_theme_compiler_cache.defer_get_set(key) { raise "genuine compiler version hit recomputed" }')
        context.write_text(text)
        (self.path / "original_theme_array_context.rb").write_text('''require_relative "list_layout_original_context"
require_relative "list_compiler_original_context"
class ObservedOriginalCategoryCache
  def defer_get_set_assets(key)
    defer_get_set(key) do
      value = yield
      CategoryCacheBootstrap.lease.note_theme_array(key, value)
      value
    end
  end
end
module ListThemeCompilerSource
  def self.targets; ListThemeArraySource::TARGETS; end
  module JavascriptCache
    def self.where(**options); ::JavascriptCache.where(**options).to_a; end
  end
  def self.get_set_cache(key)
    cache = CategoryCacheBootstrap.theme_compiler_cache
    key == "compiler_version" ? cache.defer_get_set(key) { yield } : cache.defer_get_set_assets(key) { yield }
  end
end
module ObservedOriginalCompilerHelpers
  def theme_js_assets
    @events << "theme_compiler_version_acquisition"
    value = OriginalCompilerHelpers.instance_method(:theme_js_assets).bind(self).call
    raise HtmlRenderingBoundary, 'actual Theme extra_js Array cache acquired; remaining import-map asset graph pending'
  end
end
''')
        entry = self.path / "entry.rb"
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "theme_array_transport"\nrequire_relative "native_theme_array_context"\nCategoryCacheBootstrap.configure('))

    def verify_continuation(self):
        ImportMapCompilerStageRun.verify_continuation(self)
        values = [lifecycle(self, n)["theme_compiler_cache"] for n in ("native", "compat", "compat-original")]
        assert values[0] == values[1] == values[2]
        arrays = {k: v for k, v in values[0].items() if ':extra_js:' in k}
        assert arrays and all(isinstance(v, list) for v in arrays.values())
        controls = {}
        for fault, expected in (("wrong-wire", "category cache publication scope"), ("wrong-marshal-flag", "category cache publication scope"), ("missing-array-publication", "missing category cache publication"), ("rebake-required", "unowned Theme asset rebake PG effects refused before dispatch")):
            self.env["FIDELITY_ARRAY_FAULT"] = fault
            for runtime, argv in (("native", [self.path / "probe"]), ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
                name = runtime + "-array-" + fault
                code, _ = self.command(name, argv, check=False, timeout=120)
                assert code != 0 and expected in (self.path / (name + ".stderr")).read_text(), name
                lifecycle(self, name)
                assert self.evidence["owned_cache_cleanup"][name] and self.evidence["owned_vm_source_cleanup"][name]
                controls[name] = {"returncode": code, "expected_error": expected, "fixtures_cleaned": True}
        del self.env["FIDELITY_ARRAY_FAULT"]
        self.evidence.update(theme_array_values=arrays, theme_array_acquired=True, bake_pg_dispatched=False, array_controls=controls)

    def command(self, name, argv, **kwargs):
        if name.startswith("compat"):
            tree = self.path / ("compat-preflight" if name == "compat-preflight" else "compat")
            if tree.exists():
                for item in ARRAY_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        if name == "compat-original":
            entry = self.path / "compat/entry-original.rb"
            entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "list_layout_original_context"\nrequire_relative "list_compiler_original_context"\nrequire_relative "original_theme_array_context"\nCategoryCacheBootstrap.configure('))
        return super().command(name, argv, **kwargs)

if __name__ == "__main__":
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ThemeArrayStageRun())
