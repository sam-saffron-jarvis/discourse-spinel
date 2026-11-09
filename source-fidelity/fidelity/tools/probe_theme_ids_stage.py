#!/usr/bin/env python3
"""Actual Theme.theme_ids Integer Array cache, no stylesheet/base or page acceptance."""
import json
import os
import shutil
from pathlib import Path
from probe_stylesheet_manager_read_stage import StylesheetManagerReadStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

IDS_FILES = ('theme_ids_cache_source.rb', 'theme_ids_source.rb', 'original_theme_ids_source.rb', 'theme_ids_stylesheet_source.rb', 'theme_ids_context.rb', 'theme_ids_original_context.rb', 'theme_ids_read.rb')

class ThemeIdsStageRun(StylesheetManagerReadStageRun):
    success_status = 'PASS_SCOPED_ACTUAL_THEME_IDS_INTEGER_ARRAY_CACHE_O0'
    expected_locale_boundary = 'actual Theme ID Integer cache acquired; ColorScheme lookup/base acquisition pending'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-theme-ids-stage', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_theme_ids_stage.rb', self.path], cwd=ROOT / 'discourse')
        proof = json.loads((self.path / 'theme-ids-source-proof.json').read_text())
        self.evidence['theme_ids_source'] = proof
        serving = Path(self.asset_provenance['root'])
        for relative, expected in proof['sources'].items():
            assert digest((serving / relative).read_bytes()) == expected
            self.asset_provenance['files'][relative] = expected
        (self.path / 'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance, indent=2) + '\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']), sha256=digest((self.path / 'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in IDS_FILES:
            source = HERE / 'test' / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        source = self.path / 'theme_ids_source.rb'
        text = source.read_text().replace('def self.get_set_cache_ids(key)', 'def self.get_set_cache_ids(key)\n  key = "wrong_theme_ids" if ENV.fetch("FIDELITY_THEME_IDS_FAULT", "") == "wrong-key"')
        source.write_text(text)
        context = self.path / 'stylesheet_manager_read_context.rb'
        text = context.read_text()
        stop = "    raise HtmlRenderingBoundary, 'actual stylesheet manager acquired; color stylesheet cache/read capability pending; writes remain prohibited'"
        assert text.count(stop) == 1
        context.write_text(text.replace(stop, '    manager.acquire_color_theme_ids'))
        transport = self.path / 'category_cache_transport.rb'
        text = transport.read_text()
        anchor = 'key == "compiler_version" || '
        assert text.count(anchor) == 1
        transport.write_text(text.replace(anchor, 'key == "compiler_version" || key == "theme_ids" || '))
        transport = self.path / 'theme_array_transport.rb'
        text = transport.read_text()
        anchor = '  def admitted_value?(data)\n'
        assert text.count(anchor) == 1
        transport.write_text(text.replace(anchor, anchor + '    return admitted_theme_ids_value?(data) if data["hash_key"] == theme_cache_key && data["key"] == "theme_ids"\n'))
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
        text = context.read_text()
        warms = [line.strip() for line in text.splitlines() if 'hit = lease.svg_theme_settings_key?(key)' in line and 'genuine Theme Array hit recomputed' in line]
        assert len(warms) == 1
        warm = warms[0]
        assert text.count(warm) == 1
        text = text.replace(warm, '''if key == "theme_ids"
              hit = acquired_theme_compiler_cache.defer_get_set_ids(key) { raise "Theme IDs warm cache recomputed" }
              ThemeIdsRead.verify_warm(acquired_theme_compiler_cache, value)
            else
              ''' + warm + '\n            end')
        context.write_text(text)
        entry = self.path / 'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "theme_ids_context"\nCategoryCacheBootstrap.configure('))
        original = self.path / 'stylesheet_manager_read_original_context.rb'
        original.write_text(original.read_text() + '\nrequire_relative "theme_ids_original_context"\n')
        shutil.copyfile(HERE / 'test/theme_ids.rbs', self.path / 'emitted/runtime/theme_ids.rbs')

    def faults(self):
        return (('wrong-key', 'Theme ID cache key'), ('wrong-type', 'Theme IDs require Integer Array'), ('wrong-wire', 'category cache publication scope'), ('wrong-marshal-flag', 'category cache publication scope'), ('missing-publication', 'missing category cache publication'), ('copied-warm', 'Theme IDs warm cache identity changed'), ('wrong-runtime', 'category cache runtime ownership'), ('shared-endpoint', 'protected/unknown cache endpoint'), ('unknown-endpoint', 'protected/unknown cache endpoint'))

    ids_cleanup_families = ('owned_cache_cleanup', 'owned_vm_source_cleanup', 'asset_lease_cleanup', 'owned_mf_source_cleanup')

    def check_ids_controls(self, preflight=False):
        controls = {}
        for fault, expected in self.faults():
            self.env['FIDELITY_THEME_IDS_FAULT'] = fault
            try:
                runtimes = [('compat-preflight', ['bundle', 'exec', 'ruby', self.path / 'compat-preflight/entry.rb'])] if preflight else [('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])]
                for runtime, argv in runtimes:
                    name = runtime + '-theme-ids-' + fault
                    trace = self.path / (name + '.trace')
                    code, _ = self.command(name, ['strace', '-f', '-e', 'trace=connect', '-o', trace, *argv], check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert all(self.evidence[key][name] for key in self.ids_cleanup_families)
                    port = self.evidence['owned_cache_runtime_effects'][name]['port']
                    connections = [line for line in trace.read_text().splitlines() if 'connect(' in line]
                    assert all('inet_addr("127.0.0.1")' in line and ('htons(5499)' in line or f'htons({port})' in line) for line in connections), (name, connections)
                    controls[name] = {'returncode': code, 'all_fixtures_cleaned': True, 'foreign_connections': False}
            finally:
                del self.env['FIDELITY_THEME_IDS_FAULT']
        self.evidence['theme_ids_preflight_controls' if preflight else 'theme_ids_controls'] = controls

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.check_ids_controls(preflight=True)

    def verify_continuation(self):
        super().verify_continuation()
        values = []
        for name in ('native', 'compat', 'compat-original'):
            record = lifecycle(self, name)
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_THEME_ID_CACHE ')]
            assert len(rows) == 1, name
            value = rows[0]
            assert value['integer_array'] and value['mutable'] and value['warm_identity'] and not value['warm_requeried']
            computed = [json.loads(row) for row in value['computed_vectors_json']]
            assert value['acquisitions'] > 0 and len(computed) == value['acquisitions']
            assert all(type(item) is int for row in computed for item in row)
            assert value['ids'] in computed
            assert record['theme_compiler_cache']['theme_ids'] == record['server_theme_compiler_values']['theme_ids'] == value['ids']
            values.append(value)
        assert all(value['ids'] == values[0]['ids'] and value['consumer_theme_ids_json'] == values[0]['consumer_theme_ids_json'] for value in values)
        self.check_ids_controls()
        self.evidence.update(actual_theme_ids_cache=values, theme_ids_cache_acquired=True, forced_synchronization=False, stylesheet_acquired=False, full_layout_completed=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in IDS_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ThemeIdsStageRun())
