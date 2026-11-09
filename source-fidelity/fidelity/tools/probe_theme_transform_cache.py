#!/usr/bin/env python3
"""Actual three required transform Integer-cache keys, existing lifecycle only."""
import json
import os
import shutil
from probe_stylesheet_key_read import StylesheetKeyReadRun
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

FILES = ('theme_transform_cache_source.rb', 'original_theme_transform_cache_source.rb', 'theme_transform_cache_context.rb', 'theme_transform_cache_original_context.rb')

class ThemeTransformCacheRun(StylesheetKeyReadRun):
    component_success_status = 'PASS_SCOPED_ACTUAL_THEME_TRANSFORM_CACHE_NOT_STYLESHEET'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-theme-transform-cache', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_theme_transform_cache.rb', self.path], cwd=ROOT / 'discourse')
        self.evidence['theme_transform_source'] = json.loads((self.path / 'theme-transform-cache-source-proof.json').read_text())

    def generate(self):
        super().generate()
        shutil.copyfile(HERE / 'test/theme_transform_cache_context.rb', self.path / 'theme_transform_cache_context.rb')
        (self.path / 'theme_transform_cache_original_context.rb').write_text('''require_relative 'original_theme_transform_cache_source'
module ThemeTransformRead
  def self.source_transform(id); OriginalRequestThemeTransformSource.transform_ids(id); end
  def self.source_parent; OriginalRequestThemeTransformSource.parent_theme_ids; end
  def self.source_components(id); OriginalRequestThemeTransformSource.components_for(id); end
  def self.source_parent?(id); OriginalRequestThemeTransformSource.is_parent_theme?(id); end
end
class ObservedOriginalCategoryCache
  alias_method :before_transform_defer_get_set, :defer_get_set
  def defer_get_set(key)
    return before_transform_defer_get_set(key) { yield } unless ThemeTransformRead.key?(key)
    before_transform_defer_get_set(key) do
      value = yield
      CategoryCacheBootstrap.lease.note_transform_ids(key, value)
      value
    end
  end
end
''')
        entry = self.path / 'entry.rb'
        text = entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "theme_transform_cache_context"\nThemeTransformRead.configure(SiteSetting.default_theme_id)\nCategoryCacheBootstrap.configure(')
        entry.write_text(text.replace('StylesheetKeyRead.acquire', 'StylesheetKeyRead.acquire\nThemeTransformRead.acquire'))
        original = self.path / 'stylesheet_key_original_context.rb'
        original.write_text(original.read_text() + '\nrequire_relative "theme_transform_cache_original_context"\n')
        # The raw cache class is loaded before the entry's configure call. The
        # original context's tail installs this observation wrapper after it.
        transport = self.path / 'category_cache_transport.rb'
        text = transport.read_text().replace('key == "compiler_version" || key == "theme_ids"', 'key == "compiler_version" || key == "theme_ids" || ThemeTransformRead.key?(key)')
        text = text.replace('  def admitted_value?(data)\n', '  def admitted_value?(data)\n    return admitted_transform_ids_value?(data) if data["hash_key"] == theme_cache_key && ThemeTransformRead.key?(data["key"])\n')
        transport.write_text(text)
        path = self.path / 'theme_ids_cache_source.rb'
        text = path.read_text().replace('ThemeIdsRead.check_key(k)', 'ThemeTransformRead.check_key(k)')
        text = text.replace('CategoryCacheBootstrap.lease.note_theme_ids(k, value)', 'if ThemeTransformRead.key?(k)\n      CategoryCacheBootstrap.lease.note_transform_ids(k, value)\n    else\n      CategoryCacheBootstrap.lease.note_theme_ids(k, value)\n    end')
        text = text.replace("ENV.fetch('FIDELITY_THEME_IDS_FAULT', '') == 'copied-warm'", "k == 'theme_ids' && ENV.fetch('FIDELITY_THEME_IDS_FAULT', '') == 'copied-warm'")
        text = text.replace('      return k ==', '      return hit.dup if ThemeTransformRead.key?(k) && ENV.fetch("FIDELITY_TRANSFORM_IDS_FAULT", "") == "copied-warm"\n      return k ==')
        path.write_text(text)
        bus = self.path / 'category_cache_bus_source.rb'
        text = bus.read_text().replace('value = Base64.encode64(Marshal.dump(value)) if marshal', 'value = Base64.encode64(Marshal.dump(value)) if marshal\n        value += "tampered" if ThemeTransformRead.key?(key) && ENV.fetch("FIDELITY_TRANSFORM_IDS_FAULT", "") == "wrong-wire"')
        bus.write_text(text)
        context = self.path / 'category_cache_context.rb'
        text = context.read_text().replace('ThemeIdsRead.verify_warm(acquired_theme_compiler_cache, value)\n            else', 'ThemeIdsRead.verify_warm(acquired_theme_compiler_cache, value)\n            elsif ThemeTransformRead.key?(key)\n              hit = acquired_theme_compiler_cache.defer_get_set_ids(key) { raise "Theme transform warm recomputed" }\n              ThemeTransformRead.verify_warm(key, value)\n            else')
        context.write_text(text)
        (self.path / 'emitted/runtime/theme_transform_cache.rbs').write_text('''module RequestThemeTransformSource
  def self.cache: () -> CategoryCacheApplication::DistributedCache
  def self.get_set_cache_ids: (String key) { () -> Array[Integer] } -> Array[Integer]
  def self.parent_theme_ids: () -> Array[Integer]
  def self.is_parent_theme?: (Integer id) -> bool
  def self.components_for: (Integer theme_id) -> Array[Integer]
  def self.transform_ids: (Integer? id) -> Array[Integer]
end
module ThemeTransformRead
  @theme_id: Integer
  @computed: Hash[String, Array[String]]
  @acquisitions: Hash[String, Integer]
  def self.configure: (Integer id) -> nil
  def self.key?: (untyped key) -> bool
  def self.check_key: (String key) -> nil
  def self.observe: (String key, Array[Integer] value) -> nil
  def self.source_transform: (Integer? id) -> Array[Integer]
  def self.source_parent: () -> Array[Integer]
  def self.source_parent?: (Integer id) -> bool
  def self.source_components: (Integer id) -> Array[Integer]
  def self.source_for: (String key) -> Array[Integer]
  def self.acquire: () -> nil
  def self.verify_warm: (String key, untyped value) -> nil
end
class CategoryCacheLease
  @transform_encodings: Hash[String, Array[String]]?
  def note_transform_ids: (String key, Array[Integer] value) -> nil
  def admitted_transform_ids_value?: (Hash[String, untyped] data) -> bool
end
''')

    def transform_controls(self, preflight=False):
        results = {}
        for fault, expected in (('wrong-key', 'Theme transform cache key'), ('wrong-type', 'Theme IDs require Integer Array'), ('wrong-wire', 'category cache publication scope'), ('copied-warm', 'Theme transform warm identity changed')):
            self.env['FIDELITY_TRANSFORM_IDS_FAULT'] = fault
            try:
                runtimes = [('compat-preflight', ['bundle', 'exec', 'ruby', self.path / 'compat-preflight/entry.rb'])] if preflight else [('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])]
                for runtime, argv in runtimes:
                    name = runtime + '-transform-ids-' + fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert self.evidence['owned_cache_cleanup'][name]
                    results[name] = {'returncode': code, 'fixture_cleanup': True}
            finally:
                del self.env['FIDELITY_TRANSFORM_IDS_FAULT']
        self.evidence['transform_preflight_controls' if preflight else 'transform_controls'] = results

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.transform_controls(preflight=True)

    def verify_component_extension(self):
        super().verify_component_extension()
        rows = []
        for runtime in ('native', 'compat', 'compat-original'):
            values = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (runtime + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_THEME_TRANSFORM_CACHE ')]
            assert len(values) == 3 and len({v['key'] for v in values}) == 3, (runtime, values)
            assert all(v['warm_identity'] and v['acquisitions'] > 0 and json.dumps(v['ids'], separators=(',', ':')) in v['computed_vectors_json'] for v in values)
            rows.append({v['key']: v['ids'] for v in values})
        assert rows[0] == rows[1] == rows[2]
        self.transform_controls()
        self.evidence.update(actual_theme_transform_cache=rows[0], forced_synchronization=False, stylesheet_acquired=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    ThemeTransformCacheRun().run_component()
