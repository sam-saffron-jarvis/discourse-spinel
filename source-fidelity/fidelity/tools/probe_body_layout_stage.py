#!/usr/bin/env python3
"""Actual config/auth/body/full splash before prohibited stylesheet effects, never page acceptance."""
import json
import os
import shutil
from pathlib import Path
from probe_client_meta_stage import ClientMetaStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

BODY_LAYOUT_FILES = ('body_layout_read_source.rb', 'body_layout_source.rb', 'original_body_layout_source.rb', 'body_layout_template.rb', 'original_body_layout_template.rb', 'body_splash_template.rb', 'original_body_splash_template.rb', 'body_layout_context.rb', 'body_layout_original_context.rb')

class BodyLayoutStageRun(ClientMetaStageRun):
    success_status = 'PASS_SCOPED_ACTUAL_CONFIG_AUTH_BODY_SPLASH_BEFORE_STYLESHEET_EFFECTS_O0'
    expected_locale_boundary = 'actual config/auth/body/splash returned; stylesheet effects prohibited'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-body-layout-stage', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_body_layout_stage.rb', self.path], cwd=ROOT / 'discourse')
        proof = json.loads((self.path / 'body-layout-source-proof.json').read_text())
        self.evidence['body_layout_source'] = proof
        serving = Path(self.asset_provenance['root'])
        for relative, expected in proof['sources'].items():
            assert digest((serving / relative).read_bytes()) == expected
            self.asset_provenance['files'][relative] = expected
        (self.path / 'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance, indent=2) + '\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']), sha256=digest((self.path / 'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in BODY_LAYOUT_FILES:
            source = HERE / 'test' / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        context = self.path / 'client_meta_context.rb'
        text = context.read_text()
        assert text.count('  def expected_body_events\n') == 1
        text = text.replace('def [](key); @jar.client_meta_nullable_read(key); end', 'def [](key); BodyLayoutRead.note_cookie(key); @jar.client_meta_nullable_read(key); end\n  def delete(key, path:); raise ArgumentError, "unsupported authentication cookie deletion"; end')
        context.write_text(text.replace('  def expected_body_events\n', '  def expected_client_meta_events\n'))
        context = self.path / 'locale_layout_context.rb'
        text = context.read_text()
        assert text.count('  def render(name = nil, partial: nil, opts: nil)\n') == 1
        context.write_text(text.replace('  def render(name = nil, partial: nil, opts: nil)\n', '  def render_before_body_tail(name = nil, partial: nil, opts: nil)\n'))
        context = self.path / 'list_color_context.rb'
        text = context.read_text()
        assert text.count('unless name == "header_background"') == 1
        context.write_text(text.replace('unless name == "header_background"', 'unless ["header_background", "secondary", "tertiary"].include?(name)'))
        transport = self.path / 'category_cache_transport.rb'
        text = transport.read_text()
        assert text.count('key.match?(/\\Aheader_background(?:_[0-9]+)?\\z/)') == 1
        transport.write_text(text.replace('key.match?(/\\Aheader_background(?:_[0-9]+)?\\z/)', 'key.match?(/\\A(?:header_background|secondary|tertiary)(?:_-?[0-9]+)?\\z/)'))
        entry = self.path / 'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "body_layout_context"\nCategoryCacheBootstrap.configure('))
        original = self.path / 'client_meta_original_context.rb'
        original.write_text(original.read_text() + '\nrequire_relative "body_layout_original_context"\n')
        (self.path / 'emitted/runtime/body_layout.rbs').write_text('''module BodyLayoutRead
  @extra_body_classes: Set[String]?
  def self.extra_body_classes: () -> Set[String]
  def self.source_upload: () -> Upload?
  def self.checked_upload: () -> Upload?
  def self.note_cookie: (Symbol key) -> nil
  def self.auth_cookie_reads: () -> Integer
end
module BodyLayoutSource
  def source_config_environment: (?testing: bool) -> String
  def source_authentication_data: () -> String?
  def source_body_classes: () -> String
  def source_custom_splash_screen_enabled?: () -> bool
  def source_include_splash_screen?: () -> bool
end
class ListBodyContext
  @authentication_data: String?
  @custom_splash_screen_enabled: bool?
  @body_config_json: String?
  @body_class_value: String?
  @body_authentication: String?
  @body_splash_output: String?
  @body_splash_enabled: bool?
  def u: (String value) -> String
  def splash_screen_image_animated?: () -> bool
end
''')

    def body_layout_faults(self):
        return (('wrong-config-json', 'body layout JSON/URI serialization changed'), ('wrong-uri-escape', 'body layout JSON/URI serialization changed'), ('wrong-body-class', 'body layout actual body class changed'), ('wrong-splash-predicate', 'body view-flow ordering changed'), ('drop-splash', 'body layout actual splash missing'))

    def check_body_layout_controls(self, preflight=False):
        controls = {}
        for fault, expected in self.body_layout_faults():
            self.env['FIDELITY_BODY_LAYOUT_FAULT'] = fault
            try:
                runtimes = [('compat-preflight', ['bundle', 'exec', 'ruby', self.path / 'compat-preflight/entry.rb'])] if preflight else [('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])]
                for runtime, argv in runtimes:
                    name = runtime + '-body-layout-' + fault
                    code, _ = self.command(name, argv, check=False, timeout=120)
                    assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), (name, code)
                    lifecycle(self, name)
                    assert all(self.evidence[key][name] for key in ('owned_cache_cleanup', 'owned_vm_source_cleanup', 'asset_lease_cleanup', 'owned_mf_source_cleanup'))
                    controls[name] = {'returncode': code, 'all_fixtures_cleaned': True}
            finally:
                del self.env['FIDELITY_BODY_LAYOUT_FAULT']
        self.evidence['body_layout_preflight_controls' if preflight else 'body_layout_controls'] = controls

    def compat_diagnostic(self):
        super().compat_diagnostic()
        self.check_body_layout_controls(preflight=True)

    def verify_continuation(self):
        super().verify_continuation()
        values = []
        for name in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            items = [row['template_prefix']['body_layout'] for row in rows]
            assert len(items) == 2 and items[0] == items[1]
            assert items[0]['stylesheet_called_before_effects'] and not items[0]['stylesheet_acquired'] and not items[0]['full_layout_completed']
            assert items[0]['authentication_nil_memo'] and items[0]['custom_image_nil']
            values.append(items[0])
        assert all(value == values[0] for value in values)
        self.check_body_layout_controls()
        self.evidence.update(actual_body_layout=values[0], splash_partial_completed=True, config_environment_acquired=True, stylesheet_effects_attempted=False, stylesheet_acquired=False, full_layout_completed=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in BODY_LAYOUT_FILES:
                    shutil.copyfile(self.path / item, tree / item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(BodyLayoutStageRun())
