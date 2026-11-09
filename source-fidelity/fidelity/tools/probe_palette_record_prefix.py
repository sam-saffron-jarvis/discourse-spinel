#!/usr/bin/env python3
"""Real palette lookup/unsaved constructor/SCSS attribute prefix, NOT complete base palette."""
import json
import os
import shutil
from probe_theme_ids_component import ThemeIdsComponentRun
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

PALETTE_FILES = ('palette_record_prefix_source.rb', 'original_palette_record_prefix_source.rb', 'palette_record_prefix_context.rb', 'palette_record_prefix_original_context.rb')

class PaletteRecordPrefixRun(ThemeIdsComponentRun):
    additional_schema_tables = ThemeIdsComponentRun.additional_schema_tables + ('color_schemes',)
    component_success_status = 'PASS_SCOPED_REAL_PALETTE_LOOKUP_UNSAVED_CTOR_SCSS_PREFIX_NOT_BASE'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-palette-record-prefix', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_palette_record_prefix.rb', app, self.path], cwd=ROOT / 'discourse')
        self.evidence['palette_record_prefix_source'] = json.loads((self.path / 'palette-record-prefix-source-proof.json').read_text())

    def generate(self):
        super().generate()
        shutil.copyfile(HERE / 'test/palette_record_prefix_context.rb', self.path / 'palette_record_prefix_context.rb')
        (self.path / 'palette_record_prefix_original_context.rb').write_text('''require_relative 'original_palette_record_prefix_source'
module PaletteRecordRead
  def self.factory_acquire; OriginalPaletteRecordPrefix.acquire; end
  def self.factory_record; OriginalPaletteRecordPrefix.record; end
  def self.factory_attributes; OriginalPaletteRecordPrefix.color_attributes; end
  def self.factory_colors; OriginalPaletteRecordPrefix.base_colors; end
end
''')
        entry = self.path / 'entry.rb'
        text = entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "palette_record_prefix_context"\nCategoryCacheBootstrap.configure(')
        entry.write_text(text.replace('2.times { ThemeIdsRead.source_ids }', '2.times { ThemeIdsRead.source_ids }\nPaletteRecordRead.acquire'))
        original = self.path / 'theme_ids_component_original_binding.rb'
        original.write_text(original.read_text() + '\nrequire_relative "palette_record_prefix_original_context"\n')
        (self.path / 'emitted/runtime/palette_record_prefix.rbs').write_text('''module PaletteRecordPrefix
  @base_colors: Hash[String, String]?
  @record: ColorScheme?
  @color_attributes: Array[Hash[Symbol, String]]?
  def self.base_colors: () -> Hash[String, String]
  def self.new: (**untyped attrs) -> ColorScheme
  def self.acquire: () -> nil
  def self.record: () -> ColorScheme?
  def self.color_attributes: () -> Array[Hash[Symbol, String]]?
end
module PaletteRecordRead
  def self.factory_acquire: () -> nil
  def self.factory_record: () -> ColorScheme?
  def self.factory_attributes: () -> Array[Hash[Symbol, String]]?
  def self.factory_colors: () -> Hash[String, String]
  def self.acquire: () -> nil
end
''')

    def palette_controls(self, preflight=False):
        controls = {}
        for fault, expected in (('wrong-id', 'palette constructor source id changed'), ('persisted', 'palette constructor is not unsaved ActiveRecord'), ('wrong-color', 'palette next colors writer attributes changed')):
            self.env['FIDELITY_PALETTE_PREFIX_FAULT'] = fault
            try:
                runtimes = [('compat-preflight', ['bundle', 'exec', 'ruby', self.path / 'compat-preflight/entry.rb'])] if preflight else [('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])]
                for runtime, argv in runtimes:
                    name = runtime + '-palette-prefix-' + fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert self.evidence['owned_cache_cleanup'][name]
                    controls[name] = {'returncode': code, 'owned_fixture_cleanup': True}
            finally:
                del self.env['FIDELITY_PALETTE_PREFIX_FAULT']
        self.evidence['palette_prefix_preflight_controls' if preflight else 'palette_prefix_controls'] = controls

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.palette_controls(preflight=True)

    def verify_component_extension(self):
        super().verify_component_extension()
        values = []
        for runtime in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (runtime + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_PALETTE_RECORD_PREFIX ')]
            assert len(rows) == 1 and rows[0]['constructor']['new_record'] and not rows[0]['constructor']['persisted']
            assert rows[0]['source_colors'] and rows[0]['scss_memo_identity']
            assert not rows[0]['unsaved_collection_writer_acquired'] and not rows[0]['source_base_flags_applied']
            values.append(rows[0])
        assert all(value == values[0] for value in values)
        self.palette_controls()
        self.evidence.update(actual_palette_record_prefix=values[0], full_base_palette_acquired=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in PALETTE_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    PaletteRecordPrefixRun().run_component()
