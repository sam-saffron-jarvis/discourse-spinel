#!/usr/bin/env python3
"""Actual stylesheet manager read prefix only; never a stylesheet or effect permission."""
import json
import os
import shutil
from pathlib import Path
from probe_body_layout_stage import BodyLayoutStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

STYLE_FILES = ('stylesheet_manager_read_source.rb', 'original_stylesheet_manager_read_source.rb', 'stylesheet_manager_read_context.rb', 'stylesheet_manager_read_original_context.rb')

class StylesheetManagerReadStageRun(BodyLayoutStageRun):
    success_status = 'PASS_SCOPED_ACTUAL_STYLESHEET_MANAGER_READ_PREFIX_O0_NOT_STYLESHEET'
    expected_locale_boundary = 'actual stylesheet manager acquired; color stylesheet cache/read capability pending; writes remain prohibited'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-stylesheet-manager-read-stage', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_stylesheet_manager_read_stage.rb', self.path], cwd=ROOT / 'discourse')
        proof = json.loads((self.path / 'stylesheet-manager-read-source-proof.json').read_text())
        self.evidence['stylesheet_manager_read_source'] = proof
        serving = Path(self.asset_provenance['root'])
        for relative, expected in proof['sources'].items():
            assert digest((serving / relative).read_bytes()) == expected
            self.asset_provenance['files'][relative] = expected
        (self.path / 'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance, indent=2) + '\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']), sha256=digest((self.path / 'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in STYLE_FILES:
            source = HERE / 'test' / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        context = self.path / 'body_layout_context.rb'
        text = context.read_text()
        boundary = "      raise HtmlRenderingBoundary, 'actual config/auth/body/splash returned; stylesheet effects prohibited'"
        assert text.count(boundary) == 1
        context.write_text(text.replace(boundary, "      # Execute the actual first partial expression, preserving receiver/args.\n      @output_buffer.append = discourse_color_scheme_stylesheets\n      raise 'stylesheet source read boundary unexpectedly returned'"))
        source = self.path / 'stylesheet_manager_read_source.rb'
        text = source.read_text().replace('if defined?(@stylesheet_manager)', 'if defined?(@stylesheet_manager) && ENV.fetch("FIDELITY_STYLESHEET_READ_FAULT", "") != "fresh-manager"')
        source.write_text(text)
        entry = self.path / 'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "stylesheet_manager_read_context"\nCategoryCacheBootstrap.configure('))
        original = self.path / 'body_layout_original_context.rb'
        original.write_text(original.read_text() + '\nrequire_relative "stylesheet_manager_read_original_context"\n')
        (self.path / 'emitted/runtime/stylesheet_manager_read.rbs').write_text('''class RequestStyleReadManager
  @theme_id: Integer?
  @theme_ids: Array[Integer]
  @themes_cache: Hash[Integer, Theme]
  def initialize: (?theme_id: Integer?) -> void
  def acquired_theme_id: () -> Integer?
  def acquired_theme_ids: () -> Array[Integer]
  def acquired_themes_cache: () -> Hash[Integer, Theme]
  def color_scheme_stylesheet_link_tag_href: (?Integer? id, ?fallback_to_base: bool) -> bot
end
module StylesheetManagerReadSource
  def source_stylesheet_manager: () -> RequestStyleReadManager
  def discourse_color_scheme_stylesheets: () -> bot
end
module StylesheetManagerReadBoundary
  @manager: RequestStyleReadManager?
  @scheme_id: Integer?
  def self.acquire: (RequestStyleReadManager manager, Integer? id, bool fallback) -> bot
  def self.manager: () -> RequestStyleReadManager?
  def self.scheme_id: () -> Integer?
end
class ListBodyContext
  @stylesheet_manager: RequestStyleReadManager?
end
''')

    def verify_continuation(self):
        super().verify_continuation()
        values = []
        for name in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            items = [row['template_prefix']['stylesheet_manager_read'] for row in rows]
            assert len(items) == 2 and items[0] == items[1]
            assert items[0]['source_warm_identity'] and not any(items[0][key] for key in ('stylesheet_cache_registered', 'color_stylesheet_href_acquired', 'stylesheet_acquired', 'effects_attempted'))
            values.append(items[0])
        assert all(value == values[0] for value in values)
        controls = {}
        for fault, expected in (('wrong-theme-ids', 'stylesheet source constructor transformed ids differ'), ('fresh-manager', 'stylesheet source manager warm identity changed')):
            self.env['FIDELITY_STYLESHEET_READ_FAULT'] = fault
            try:
                for runtime, argv in (('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])):
                    name = runtime + '-stylesheet-read-' + fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert all(self.evidence[key][name] for key in ('owned_cache_cleanup', 'owned_vm_source_cleanup', 'asset_lease_cleanup', 'owned_mf_source_cleanup'))
                    controls[name] = {'returncode': code, 'all_fixtures_cleaned': True}
            finally:
                del self.env['FIDELITY_STYLESHEET_READ_FAULT']
        self.evidence.update(actual_stylesheet_manager_read=values[0], stylesheet_manager_read_controls=controls, stylesheet_acquired=False, stylesheet_effects_attempted=False, full_layout_completed=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in STYLE_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(StylesheetManagerReadStageRun())
