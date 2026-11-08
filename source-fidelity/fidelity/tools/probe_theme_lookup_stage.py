#!/usr/bin/env python3
"""Actual readonly Theme field query/lookup and original bulk nil cache, not a page."""
import json
import os
import shutil
from theme_bulk_capability import ThemeBulkCapabilityRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

FIELD_FILES = ('theme_lookup_source.rb', 'original_theme_lookup_source.rb', 'theme_lookup_helpers.rb', 'theme_lookup_context.rb', 'theme_lookup_original_context.rb')

class ThemeLookupStageRun(ThemeBulkCapabilityRun):
    success_status = 'PASS_SCOPED_ACTUAL_THEME_TRANSLATION_BULK_BEFORE_CORE_PRELOAD'
    expected_locale_boundary = 'core browser-detect preload acquisition pending'
    allow_field_cache = True

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-theme-lookup-stage', ['bundle', 'exec', 'ruby', HERE/'tools/generate_theme_lookup_stage.rb', app, self.path], cwd=ROOT/'discourse')
        self.evidence['theme_lookup_source'] = json.loads((self.path/'theme-lookup-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in FIELD_FILES:
            source = HERE/'test'/name
            if source.exists(): shutil.copyfile(source,self.path/name)
        (self.path/'emitted/runtime/theme_lookup.rbs').write_text('''module ListThemeCompilerSource
  def self.lookup_field: (Integer | Array[Integer] | nil theme_id, Symbol target, Symbol field, ?skip_transformation: bool, ?csp_nonce: String?) -> (ActionView::HtmlFragment | String)
  def self.resolve_baked_field: (Array[Integer] ids, Symbol target, Symbol? name) -> String
  def self.theme_field_values: (Array[Integer] ids, Symbol | Array[Symbol] targets, Symbol | Array[Symbol] names) -> Hash[Array[Integer | Symbol], Array[String]?]
  def self.theme_fallbacks: (Symbol? locale) -> Array[Symbol]
end
module ThemeFieldReadBootstrap
  @computations: Integer?
  @callback_count: Integer?
  @row_count: Integer?
  @last_keys: Array[Array[Integer | Symbol]]?
  def self.note_keys: (Array[Array[Integer | Symbol]] keys) -> nil
  def self.note_callback: () -> nil
  def self.note_read_row: () -> nil
  def self.last_keys: () -> Array[Array[Integer | Symbol]]?
end
''')
        entry = self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "theme_lookup_context"\nCategoryCacheBootstrap.configure('))
        original = self.path/'theme_bulk_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "theme_lookup_original_context"\n')

    def normalize_stage_record(self, row):
        nonce = row['template_prefix']['csp_nonce']
        item = row['template_prefix']['theme_translations']
        item['value'] = item['value'].replace(nonce, '[genuine-random-nonce]')
        return super().normalize_stage_record(row)

    def verify_continuation(self):
        super().verify_continuation()
        observations = []
        for name in ('native','compat','compat-original'):
            rows = [json.loads(line.split(' ',1)[1]) for line in (self.path/(name+'.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            items = [dict(row['template_prefix']['theme_translations'], value=row['template_prefix']['theme_translations']['value'].replace(row['template_prefix']['csp_nonce'], '[genuine-random-nonce]')) for row in rows]
            assert all(isinstance(item['value'],str) and item['query_keys'] and item['computations'] > 0 for item in items)
            assert all('js/browser-update' in row['template_prefix']['asset_urls'] for row in rows)
            observations.append(items)
        assert observations[0] == observations[1] == observations[2]
        controls = {}
        for fault, expected in (('rebake-required', 'unowned Theme field rebake PG effects refused before dispatch'), ('omit-callback', 'applicable Theme field callback omitted')):
            self.env['FIDELITY_THEME_FIELD_FAULT'] = fault
            try:
                for runtime, argv in (('native', [self.path/'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path/'compat/entry.rb'])):
                    name = runtime+'-theme-field-'+fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path/(name+'.stderr')).read_text(), name
                    lifecycle(self, name)
                    assert all(self.evidence[key][name] for key in ('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name] = {'returncode':code, 'expected_error':expected, 'all_fixtures_cleaned':True}
            finally:
                del self.env['FIDELITY_THEME_FIELD_FAULT']
        self.evidence['theme_field_controls'] = controls
        self.evidence.update(actual_theme_translations=observations[0], theme_field_query_acquired=True, pg_bake_dispatched=False, full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree = self.path/('compat-preflight' if name=='compat-preflight' else 'compat')
            if tree.exists():
                for item in FIELD_FILES: shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(ThemeLookupStageRun())
