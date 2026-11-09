#!/usr/bin/env python3
"""Real Theme ID cache on earlier real readonly request scaffold, not full layout integration."""
import json
import os
import shutil
from pathlib import Path
from probe_category_cache_stage import OriginalCacheStageRun, verify_cache, lifecycle
from probe_latest_html_stage import verify_stage
from probe_theme_ids_stage import ThemeIdsStageRun
from verify import HERE, ROOT, digest

FILES = ('theme_ids_read.rb', 'theme_ids_source.rb', 'theme_ids_cache_source.rb', 'original_theme_ids_source.rb', 'theme_ids_component_binding.rb', 'theme_ids_component_original_binding.rb')

class ThemeIdsComponentRun(OriginalCacheStageRun):
    ids_cleanup_families = ('owned_cache_cleanup',)
    faults = ThemeIdsStageRun.faults
    check_ids_controls = ThemeIdsStageRun.check_ids_controls

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-theme-ids-stage', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_theme_ids_stage.rb', self.path], cwd=ROOT / 'discourse')
        self.command('generate-theme-ids-component', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_theme_ids_component.rb', self.path], cwd=ROOT / 'discourse')
        self.evidence['theme_ids_source'] = json.loads((self.path / 'theme-ids-source-proof.json').read_text())
        self.evidence['component_source'] = json.loads((self.path / 'theme-ids-component-source-proof.json').read_text())

    def generate(self):
        super().generate()
        shutil.copyfile(HERE / 'test/theme_ids_read.rb', self.path / 'theme_ids_read.rb')
        shutil.copyfile(HERE / 'test/theme_ids.rbs', self.path / 'emitted/runtime/theme_ids.rbs')
        source = self.path / 'theme_ids_source.rb'
        text = source.read_text().replace('def self.get_set_cache_ids(key)', 'def self.get_set_cache_ids(key)\n  key = "wrong_theme_ids" if ENV.fetch("FIDELITY_THEME_IDS_FAULT", "") == "wrong-key"')
        source.write_text(text)
        entry = self.path / 'entry.rb'
        text = entry.read_text()
        requires = '\n'.join('require_relative ' + json.dumps(name[:-3]) for name in FILES if not name.startswith('original_') and 'original_binding' not in name)
        text = text.replace('\nCategoryCacheBootstrap.configure(', '\n' + requires + '\nCategoryCacheBootstrap.configure(')
        text = text.replace('require_relative "probe"', '''require_relative "probe"
# Additional source API component call on the same actual runtime/owned fixture.
# Both may legally be cold while deferred publication is pending. No sync/wait.
2.times { ThemeIdsRead.source_ids }
''')
        entry.write_text(text)
        transport = self.path / 'category_cache_transport.rb'
        text = transport.read_text().replace('data["marshalled"] == false && data["key"].is_a?(String) && data["value"].is_a?(String)', 'admitted_value?(data) && data["key"].is_a?(String)')
        text = text.replace('key == "compiler_version"', 'key == "compiler_version" || key == "theme_ids"')
        transport.write_text(text)
        with transport.open('a') as out:
            out.write('''
class CategoryCacheLease
  def admitted_value?(data)
    return admitted_theme_ids_value?(data) if data["hash_key"] == theme_cache_key && data["key"] == "theme_ids"
    data["marshalled"] == false && data["value"].is_a?(String)
  end
  def decoded_theme_value(data)
    raise 'unowned Theme IDs wire value' unless admitted_value?(data)
    data["marshalled"] ? Marshal.load(Base64.decode64(data["value"])) : data["value"]
  end
end
''')
        bus = self.path / 'category_cache_bus_source.rb'
        text = bus.read_text()
        anchor = 'value = Base64.encode64(Marshal.dump(value)) if marshal'
        assert text.count(anchor) == 1
        text = text.replace(anchor, anchor + '''
        if key == "theme_ids"
          value += "tampered" if ENV.fetch("FIDELITY_THEME_IDS_FAULT", "") == "wrong-wire"
          marshal = false if ENV.fetch("FIDELITY_THEME_IDS_FAULT", "") == "wrong-marshal-flag"
          return if ENV.fetch("FIDELITY_THEME_IDS_FAULT", "") == "missing-publication"
        end''')
        bus.write_text(text)
        context = self.path / 'category_cache_context.rb'
        text = context.read_text().replace('data["marshalled"] == false', 'lease.admitted_value?(data)')
        text = text.replace('server_theme_compiler_values[data["key"]] = data["value"]', 'server_theme_compiler_values[data["key"]] = lease.decoded_theme_value(data)')
        warm = 'hit = acquired_theme_compiler_cache.defer_get_set(key) { raise "genuine compiler version hit recomputed" }'
        assert text.count(warm) == 1
        text = text.replace(warm, '''if key == "theme_ids"
              hit = acquired_theme_compiler_cache.defer_get_set_ids(key) { raise "Theme IDs warm cache recomputed" }
              ThemeIdsRead.verify_warm(acquired_theme_compiler_cache, value)
            else
              ''' + warm + '\n            end')
        context.write_text(text)

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.check_ids_controls(preflight=True)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in FILES:
                    shutil.copyfile(self.path / item, tree / item)
        if name == 'compat-original':
            # Base inserts raw cache before configure; load observation override
            # from that existing original context's tail to retain correct order.
            original = self.path / 'category_cache_original_context.rb'
            text = original.read_text()
            anchor = '\nrequire_relative "theme_ids_component_original_binding"\n'
            if anchor not in text:
                original.write_text(text + anchor)
        return super().command(name, argv, **kwargs)

    def run_component(self):
        try:
            self.provenance()
            self.generate()
            self.command('native-compile', [ROOT / 'spinel/spinel', '--jobs=4', '-O', '0', '--int-overflow=promote', '--rbs', self.path / 'emitted', '-I', Path.home() / '.cache/spin/packages/pg-0.2.0', self.path / 'entry.rb', '-o', self.path / 'probe'])
            self.command('native', ['strace', '-f', '-e', 'trace=execve,connect', '-o', self.path / 'native.trace', self.path / 'probe'], timeout=120)
            compat = self.path / 'compat'
            shutil.copytree(self.path / 'emitted', compat / 'emitted')
            for name in ('entry.rb', 'probe.rb'):
                shutil.copyfile(self.path / name, compat / name)
            shutil.copyfile(ROOT / 'roundhouse/runtime/spinel/pg_driver_cruby.rb', compat / 'emitted/runtime/pg_driver.rb')
            self.command('compat', ['bundle', 'exec', 'ruby', '--enable-frozen-string-literal', compat / 'entry.rb'], timeout=120)
            verify_stage(self)
            verify_cache(self)
            values = []
            for runtime in ('native', 'compat', 'compat-original'):
                rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (runtime + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_THEME_ID_CACHE ')]
                assert len(rows) == 1
                value = rows[0]
                computed = [json.loads(row) for row in value['computed_vectors_json']]
                assert value['warm_identity'] and not value['warm_requeried'] and value['mutable']
                assert value['acquisitions'] > 0 and len(computed) == value['acquisitions']
                assert all(type(item) is int for row in computed for item in row) and value['ids'] in computed
                cache = lifecycle(self, runtime)
                assert cache['theme_compiler_cache']['theme_ids'] == cache['server_theme_compiler_values']['theme_ids'] == value['ids']
                values.append(value)
            assert all(v['ids'] == values[0]['ids'] for v in values)
            self.check_ids_controls()
            self.evidence.update(status='PASS_SCOPED_ACTUAL_THEME_IDS_CACHE_COMPONENT_NOT_FULL_LAYOUT', actual_theme_ids_cache=values, cumulative_layout_integration_accepted=False, forced_synchronization=False, page_accepted=False)
        except BaseException as error:
            self.evidence.update(status='FAILED_THEME_IDS_COMPONENT', error=repr(error))
            raise
        finally:
            self.save()
            print(self.path)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    ThemeIdsComponentRun().run_component()
