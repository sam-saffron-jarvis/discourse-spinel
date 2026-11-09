#!/usr/bin/env python3
"""Actual unsaved base palette/helper on real request scaffold, NOT stylesheet/page acceptance."""
import json
import os
import shutil
from probe_palette_record_prefix import PaletteRecordPrefixRun
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

BASE_FILES = ('palette_base_source.rb', 'original_palette_base_source.rb', 'palette_base_read_context.rb', 'palette_base_original_context.rb')

class PaletteBaseReadRun(PaletteRecordPrefixRun):
    additional_schema_tables = PaletteRecordPrefixRun.additional_schema_tables + ('color_scheme_colors',)
    component_success_status = 'PASS_SCOPED_ACTUAL_UNSAVED_BASE_PALETTE_NOT_STYLESHEET'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-palette-base-read', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_palette_base_read.rb', app, self.path], cwd=ROOT / 'discourse')
        self.evidence['palette_base_source'] = json.loads((self.path / 'palette-base-source-proof.json').read_text())

    def generate(self):
        super().generate()
        shutil.copyfile(HERE / 'test/palette_base_read_context.rb', self.path / 'palette_base_read_context.rb')
        (self.path / 'palette_base_original_context.rb').write_text('''require_relative 'original_palette_base_source'
module OriginalPaletteBaseSource
  module I18n
    def self.t(key)
      raise ArgumentError, 'unacquired original base palette translation' unless key == 'admin_js.admin.customize.theme.default_light_scheme'
      ::I18n.translate_runtime(key, {}, '', false, false)
    end
  end
end
module PaletteBaseRead
  def self.source_base; OriginalPaletteBaseSource.base; end
end
''')
        entry = self.path / 'entry.rb'
        text = entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "palette_base_read_context"\nCategoryCacheBootstrap.configure(')
        entry.write_text(text.replace('PaletteRecordRead.acquire', 'PaletteRecordRead.acquire\nPaletteBaseRead.acquire'))
        original = self.path / 'palette_record_prefix_original_context.rb'
        original.write_text(original.read_text() + '\nrequire_relative "palette_base_original_context"\n')
        # One precise owner declaration per source capability method; do not
        # add conflicting duplicate seeds beside the emitter's fallback hints.
        contracts = {
            'color_scheme': {
                'colors=': '(Array[Hash[Symbol, String]] arr) -> Array[Hash[Symbol, String]]',
                'source_base_palette_name!': '() -> nil',
                'source_base_palette_name_off!': '() -> nil',
                'source_raw_palette_name': '() -> String?',
                'source_unsaved_base_colors': '() -> Array[ColorSchemeColor]',
                'append_unsaved_base_color': '(ColorSchemeColor color) -> ColorScheme',
            },
            'color_scheme_color': {
                'source_attach_base_palette': '(ColorScheme owner) -> nil',
                'source_base_palette_owner': '() -> ColorScheme?',
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
        (self.path / 'emitted/runtime/palette_base_read.rbs').write_text('''module PaletteBaseSource
  @base_color_scheme: ColorScheme?
  def self.base: () -> ColorScheme
  def self.new: (**untyped attrs) -> ColorScheme
  def self.base_colors: () -> Hash[String, String]
end
module PaletteBaseRead
  @defaults: Hash[Symbol, untyped]?
  def self.build_record: (Hash[Symbol, untyped] attrs) -> ColorScheme
  def self.source_base: () -> ColorScheme
  def self.acquire: () -> nil
end
class ColorScheme
  @source_base_palette_name: bool?
  @source_unsaved_base_colors: Array[ColorSchemeColor]?
  @is_base: bool?
  @is_builtin_default: bool?
end
class ColorSchemeColor
  @source_base_palette_owner: ColorScheme?
end
''')

    def base_controls(self, preflight=False):
        controls = {}
        for fault, expected in (('wrong-flag', 'base palette source flags changed'), ('wrong-fk', 'base palette colors are not actual unsaved records'), ('persisted-child', 'base palette colors are not actual unsaved records'), ('fixed-name', 'base palette I18n name did not follow locale')):
            self.env['FIDELITY_PALETTE_BASE_FAULT'] = fault
            try:
                runtimes = [('compat-preflight', ['bundle', 'exec', 'ruby', self.path / 'compat-preflight/entry.rb'])] if preflight else [('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])]
                for runtime, argv in runtimes:
                    name = runtime + '-palette-base-' + fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert self.evidence['owned_cache_cleanup'][name]
                    controls[name] = {'returncode': code, 'fixture_cleanup': True}
            finally:
                del self.env['FIDELITY_PALETTE_BASE_FAULT']
        self.evidence['palette_base_preflight_controls' if preflight else 'palette_base_controls'] = controls

    def raw_model_reference(self):
        self.env['FIDELITY_PG_CONNECTION_LOG'] = str(self.path / 'raw-palette-pg-connections.jsonl')
        self.env['FIDELITY_ORACLE_PHASE'] = 'isolated-unsaved-palette-model-no-rails-app'
        name = 'compat-preflight-palette-base-raw-model'
        self.command(name, ['bundle', 'exec', 'ruby', self.path / 'raw_palette_base_reference.rb'], timeout=120)
        assert self.evidence['owned_cache_cleanup'][name]
        lines = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_RAW_PALETTE_BASE ')]
        assert len(lines) == 1
        pools = [json.loads(line) for line in (self.path / (name + '-cache-fixture/pg-connections.jsonl')).read_text().splitlines()]
        assert pools and all(p['database'] == 'discourse_development' and p['port'] == 5499 and p['default_transaction_read_only'] == 'on' for p in pools)
        self.evidence['raw_palette_base_model'] = {'record': lines[0], 'readonly_pools': pools, 'rails_application_or_html_invoked': False, 'owned_fixture_cleanup': True}
        return lines[0]

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.base_controls(preflight=True)
        raw = self.raw_model_reference()
        rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / 'compat-preflight.stdout').read_text().splitlines() if line.startswith('FIDELITY_PALETTE_BASE ')]
        assert len(rows) == 1 and rows[0] == raw, 'shared base palette differs from actual ActiveRecord model'

    def verify_component_extension(self):
        super().verify_component_extension()
        raw = self.evidence['raw_palette_base_model']['record']
        for runtime in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (runtime + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_PALETTE_BASE ')]
            assert len(rows) == 1 and rows[0] == raw, runtime
        self.base_controls()
        self.evidence.update(actual_base_palette=raw, full_base_palette_acquired=True, generic_singleton_or_association_proxy_api_supported=False, stylesheet_acquired=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in BASE_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    PaletteBaseReadRun().run_component()
