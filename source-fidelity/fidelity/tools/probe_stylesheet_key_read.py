#!/usr/bin/env python3
"""Actual source Slug/cache-key/read globals; NOT stylesheet or page acceptance."""
import json
import os
import shutil
from probe_palette_base_read import PaletteBaseReadRun
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

KEY_FILES = ('stylesheet_key_source.rb', 'original_stylesheet_slug.rb', 'original_stylesheet_key_source.rb', 'stylesheet_key_read_context.rb', 'stylesheet_key_original_context.rb')

class StylesheetKeyReadRun(PaletteBaseReadRun):
    component_success_status = 'PASS_SCOPED_ACTUAL_STYLESHEET_SLUG_KEY_GLOBALS_NOT_STYLESHEET'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-stylesheet-key-read', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_stylesheet_key_read.rb', app, self.path], cwd=ROOT / 'discourse')
        self.evidence['stylesheet_key_source'] = json.loads((self.path / 'stylesheet-key-source-proof.json').read_text())

    def generate(self):
        super().generate()
        shutil.copyfile(HERE / 'test/stylesheet_key_read_context.rb', self.path / 'stylesheet_key_read_context.rb')
        (self.path / 'stylesheet_key_original_context.rb').write_text('''require_relative 'original_stylesheet_slug'
require_relative 'original_stylesheet_key_source'
module StylesheetKeyRead
  def self.source_key(record, theme_id); OriginalStylesheetKeySource.color_scheme_cache_key(record, theme_id); end
  def self.source_slug(text); OriginalStylesheetSlug.for(text); end
end
''')
        entry = self.path / 'entry.rb'
        setup = 'require ' + json.dumps(str(HERE / 'compat/discourse/lib/site_settings/portable_stylesheet_slug_reader.rb')) + '\nclass SiteSetting\n  def self.slug_generation_method(scoped_to = nil); portable_store.stylesheet_slug_current(portable_site); end\nend\nrequire_relative "stylesheet_key_read_context"\nStylesheetKeyRead.configure(settings_configuration)\n'
        text = entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\n' + setup + 'CategoryCacheBootstrap.configure(')
        entry.write_text(text.replace('PaletteBaseRead.acquire', 'PaletteBaseRead.acquire\nStylesheetKeyRead.acquire'))
        original = self.path / 'palette_base_original_context.rb'
        original.write_text(original.read_text() + '\nrequire_relative "stylesheet_key_original_context"\n')
        path = self.path / 'emitted/app/models/color_scheme.rb'
        text = path.read_text().replace('value = @name', 'value = @name\n    value = self.name if ENV.fetch("FIDELITY_STYLESHEET_KEY_FAULT", "") == "localized-name"')
        path.write_text(text)
        contracts = {
            'color_scheme': {'read_attribute': '(Symbol name) -> String'},
            'slug': {
                'self.for': '(String string, ?String default, ?Integer max_length, ?method: Symbol?) -> String',
                'self.slug_is_only_numbers?': '(String slug) -> bool',
                'self.prettify_slug': '(String slug, max_length: Integer) -> String',
                'self.ascii_generator': '(String string) -> String',
                'self.encoded_generator': '(String string, ?downcase: bool) -> String',
                'self.none_generator': '(String string) -> String',
            },
        }
        for owner, methods in contracts.items():
            path = self.path / 'emitted/app/models' / (owner + '.rbs')
            lines = path.read_text().splitlines()
            for method, signature in methods.items():
                matches = [i for i, line in enumerate(lines) if line.startswith('  def ' + method + ':')]
                assert len(matches) == 1, (owner, method)
                lines[matches[0]] = '  def ' + method + ': ' + signature
            path.write_text('\n'.join(lines) + '\n')
        (self.path / 'emitted/runtime/stylesheet_key_read.rbs').write_text('''module StylesheetKeySource
  def self.color_scheme_cache_key: (ColorScheme color_scheme, ?Integer? theme_id) -> String
end
class GlobalSetting
  def self.relative_url_root: () -> String?
end
module StylesheetKeyRead
  @configuration: SiteSettings::PortableGlobalConfiguration
  def self.configure: (SiteSettings::PortableGlobalConfiguration configuration) -> nil
  def self.relative_url_root: () -> String?
  def self.source_key: (ColorScheme record, Integer? theme_id) -> String
  def self.source_slug: (String text) -> String
  def self.acquire: () -> nil
end
''')

    def key_reference(self):
        name = 'compat-preflight-stylesheet-key-raw-model'
        self.command(name, ['bundle', 'exec', 'ruby', self.path / 'raw_stylesheet_key_reference.rb'], timeout=120)
        assert self.evidence['owned_cache_cleanup'][name]
        rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_RAW_STYLESHEET_KEY ')]
        assert len(rows) == 1
        pools = [json.loads(line) for line in (self.path / (name + '-cache-fixture/pg-connections.jsonl')).read_text().splitlines()]
        assert pools and all(p['database'] == 'discourse_development' and p['port'] == 5499 and p['default_transaction_read_only'] == 'on' for p in pools)
        self.evidence['raw_stylesheet_key_model'] = {'record': rows[0], 'readonly_pools': pools, 'rails_application_or_html_invoked': False, 'owned_fixture_cleanup': True}
        return rows[0]

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.key_controls(preflight=True)
        raw = self.key_reference()
        rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / 'compat-preflight.stdout').read_text().splitlines() if line.startswith('FIDELITY_STYLESHEET_KEY ')]
        assert rows == [raw], 'shared stylesheet key differs from actual AR/ActiveSupport source'

    def verify_component_extension(self):
        super().verify_component_extension()
        raw = self.evidence['raw_stylesheet_key_model']['record']
        for runtime in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (runtime + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_STYLESHEET_KEY ')]
            assert rows == [raw], runtime
        self.key_controls()
        self.evidence.update(actual_stylesheet_key=raw, stylesheet_acquired=False, generic_unicode_transliteration_supported=False)

    def key_controls(self, preflight=False):
        controls = {}
        for fault, expected in (('non-ascii', 'unacquired non-ASCII stylesheet slug transliteration'), ('wrong-attribute', 'unacquired stylesheet raw attribute'), ('wrong-root', 'stylesheet global relative root changed'), ('localized-name', 'localized palette name changed stylesheet key')):
            self.env['FIDELITY_STYLESHEET_KEY_FAULT'] = fault
            try:
                runtimes = [('compat-preflight', ['bundle', 'exec', 'ruby', self.path / 'compat-preflight/entry.rb'])] if preflight else [('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])]
                for runtime, argv in runtimes:
                    name = runtime + '-stylesheet-key-' + fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert self.evidence['owned_cache_cleanup'][name]
                    controls[name] = {'returncode': code, 'fixture_cleanup': True}
            finally:
                del self.env['FIDELITY_STYLESHEET_KEY_FAULT']
        self.evidence['stylesheet_key_preflight_controls' if preflight else 'stylesheet_key_controls'] = controls

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in KEY_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    StylesheetKeyReadRun().run_component()
