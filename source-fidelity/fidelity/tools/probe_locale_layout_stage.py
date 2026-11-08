#!/usr/bin/env python3
"""SAME actual layout through main locale JS/preload; refuses next MF compiler."""
import json
import os
import re
import shutil
from pathlib import Path
from probe_importmap_assets_stage import ImportMapAssetsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

LOCALE_FILES = ('client_locale_registry.rb', 'request_client_locale_source.rb', 'request_client_locale_source.rbs',
                'original_client_locale_source.rb', 'original_client_locale_bindings.rb', 'original_client_fallbacks.rb',
                'request_extra_locale_source.rb', 'request_extra_locale_source.rbs', 'original_extra_locale_source.rb',
                'request_locale_layout_helpers.rb', 'original_locale_layout_helpers.rb', 'original_client_date_backend.rb',
                'native_locale_layout.rb', 'locale_layout_context.rb', 'locale_layout_original_context.rb', 'original_locale_boot.rb')

class LocaleLayoutStageRun(ImportMapAssetsStageRun):
    success_status = 'PASS_SCOPED_LAYOUT_MAIN_LOCALE_BEFORE_MESSAGEFORMAT'
    expected_locale_preload_links = 1
    expected_locale_boundary = 'MessageFormat compiler acquisition pending'
    additional_schema_tables = ImportMapAssetsStageRun.additional_schema_tables + ('translation_overrides',)

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-client-locale-source', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_client_locale_source.rb', self.path], cwd=ROOT / 'discourse')
        self.command('generate-locale-layout-stage', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_locale_layout_stage.rb', app, self.path], cwd=ROOT / 'discourse')
        self.evidence['locale_layout_source'] = json.loads((self.path / 'locale-layout-source-proof.json').read_text())
        self.evidence['client_locale_source'] = json.loads((self.path / 'client-locale-source-proof.json').read_text())
        root = Path(self.asset_provenance['root'])
        for locale in ('en', 'fr'):
            names = [root / 'config/locales' / f'{kind}.{locale}.yml' for kind in ('server', 'client')]
            names += list(root.glob(f'plugins/*/config/locales/client*.{locale}.yml'))
            names += [root / 'vendor/runtime_node_modules' / folder / f'{locale}.js' for folder in ('moment/locale', 'moment-timezone-names/locales')]
            for file in names:
                relative = str(file.relative_to(root))
                if file.is_file(): self.asset_provenance['files'][relative] = digest(file.read_bytes())
                else: self.asset_provenance['absent'].append(relative)
        (self.path / 'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance, indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']), sha256=digest((self.path / 'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in LOCALE_FILES:
            source = HERE / 'test' / name
            if source.exists(): shutil.copyfile(source, self.path / name)
        # Name concrete base adapter entrypoints; do not add another ambiguous
        # same-name mixin super chain or change any original helper branches.
        for name in ('request_asset_context.rb', 'request_asset_original_context.rb'):
            path = self.path / name
            text = path.read_text()
            assert text.count('def acquire_request_asset_bindings\n') == 1
            path.write_text(text.replace('def acquire_request_asset_bindings\n', 'def acquire_base_request_asset_bindings\n'))
        for name in ('request_client_locale_source.rbs', 'request_extra_locale_source.rbs'):
            shutil.copyfile(self.path / name, self.path / 'emitted/runtime' / name)
        (self.path / 'emitted/runtime/client_yaml_profile.rbs').write_text('''# Exact client helper profile: validated File.read String, never YAML IO input.
module Psych
  def self.sp_load: (String yaml, Psych::SpResolver resolver, bool aliases, String? filename, untyped fallback, bool symbolize_names, bool freeze) -> untyped
  class SpParser
    # YAML nested maps have genuine Boolean/Integer/String keys. This is the
    # parser's boxed map protocol, not a widening of application String caches.
    def store: (Hash[untyped, untyped] h, untyped key, untyped value, bool plain_key) -> untyped
  end
end
''')
        (self.path / 'emitted/runtime/locale_layout.rbs').write_text('''module RequestClientLocaleBootstrap
  @root: String?
  @events: Array[String]?
  @last_main_script: String?
  @main_builds: Integer?
  @date_overrides: Hash[String, Hash[String, String]]?
  def self.events: () -> Array[String]
  def self.events=: (Array[String]) -> Array[String]
  def self.main_builds: () -> Integer
  def self.date_overrides: () -> Hash[String, Hash[String, String]]
  def self.overrides: (String | Symbol locale) -> Hash[String, String]
  def self.date_translation: (String name) -> String
  def self.build_main: (String locale) -> String
end
class HtmlStageObservedController
  @asset_preload_links: Array[String]?
  attr_accessor asset_preload_links: Array[String]?
end
class ListBodyContext
  def add_resource_preload_list: (String resource_url, String type) -> Array[String]
  def preload_script_url: (String url, ?entrypoint: String?, ?type_module: bool, ?attrs: Hash[String | Symbol, String]?) -> ActionView::HtmlFragment
end
module RequestLocaleLayoutHelpers
  def preload_script_url: (String url, ?entrypoint: String?, ?type_module: bool, ?attrs: Hash[String | Symbol, String]?) -> ActionView::HtmlFragment
end
''')
        context = self.path / 'locale_layout_context.rb'
        text = context.read_text().replace('links.size == 1', 'links.size == ' + str(self.expected_locale_preload_links)).replace('links = controller.asset_preload_links', 'controller.asset_preload_links = nil if ENV.fetch("FIDELITY_LOCALE_FAULT", "") == "missing-preload"\n    links = controller.asset_preload_links')
        context.write_text(text)
        entry = self.path / 'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "locale_layout_context"\nCategoryCacheBootstrap.configure('))

    def normalize_stage_record(self, row):
        nonce = row['template_prefix']['csp_nonce']
        row = super().normalize_stage_record(row)
        view = row['template_prefix']
        assert view['layout_prefix'].count(nonce) >= 3
        view['layout_prefix'] = view['layout_prefix'].replace(nonce, '[genuine-random-nonce]')
        return row

    def verify_continuation(self):
        super().verify_continuation()
        values = []
        for name in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name+'.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                assert self.expected_locale_boundary in row['refusal']
                item = row['template_prefix']['main_locale']
                assert item['bytes'] > 0 and item['builds'] == 1
                assert len(item['digest']) == 40 and len(item['resource_preload_links']) == self.expected_locale_preload_links
                values.append(item)
        assert all(item == values[0] for item in values)
        controls = {}
        self.env['FIDELITY_LOCALE_FAULT'] = 'missing-preload'
        try:
            for runtime, argv in (('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])):
                name = runtime+'-locale-missing-preload'
                code, _ = self.command(name, argv, check=False, timeout=120)
                assert code != 0 and 'genuine main locale preload missing' in (self.path / (name+'.stderr')).read_text()
                lifecycle(self, name)
                assert self.evidence['owned_cache_cleanup'][name] and self.evidence['owned_vm_source_cleanup'][name] and self.evidence['asset_lease_cleanup'][name]
                controls[name] = {'returncode': code, 'all_owned_fixtures_cleaned': True}
        finally:
            del self.env['FIDELITY_LOCALE_FAULT']
        self.evidence.update(actual_main_locale=values[0], locale_controls=controls, actual_main_locale_preload_executed=True, mf_compiler_acquired=False, full_layout_completed=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in LOCALE_FILES: shutil.copyfile(self.path / item, tree / item)
        if name == 'compat-original':
            argv = list(argv)
            position = [str(x) for x in argv].index('ruby') + 1
            argv[position:position] = ['-r' + str(self.path / 'original_locale_boot.rb')]
            entry = self.path / 'compat/entry-original.rb'
            entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "locale_layout_original_context"\nCategoryCacheBootstrap.configure('))
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(LocaleLayoutStageRun())
