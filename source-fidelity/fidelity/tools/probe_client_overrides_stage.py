#!/usr/bin/env python3
"""Actual client override source read/output and empty-result nil cache lifecycle."""
import json
import os
import shutil
from probe_messageformat_stage import MessageFormatStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

OVERRIDE_FILES = ('client_override_context.rb', 'client_override_original_context.rb', 'client_override_layout_helpers.rb')

class ClientOverrideStageRun(MessageFormatStageRun):
    success_status = 'PASS_SCOPED_LAYOUT_CLIENT_OVERRIDE_NIL_CACHE_BEFORE_THEME'
    expected_locale_boundary = 'Theme translation bulk cache acquisition pending'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-client-overrides-stage', ['bundle', 'exec', 'ruby', HERE/'tools/generate_client_overrides_stage.rb', app, self.path], cwd=ROOT/'discourse')
        self.evidence['client_override_source'] = json.loads((self.path/'client-overrides-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in OVERRIDE_FILES:
            source = HERE/'test'/name
            if source.exists(): shutil.copyfile(source, self.path/name)
        (self.path/'emitted/runtime/client_overrides.rbs').write_text('''module RequestClientLocaleBootstrap
  @override_builds: Integer?
  @override_checks: Integer?
  @last_override_script: String?
  @override_locale: String?
  def self.override_builds: () -> Integer
  def self.override_checks: () -> Integer
  def self.record_overrides: (String value) -> String
  def self.build_overrides: (String locale) -> String
end
class ExtraLocalesController
  def self.observed_override_cache: () -> Hash[String, String?]
end
class RequestClientLocaleSource
  def client_override_json: (Hash[String, untyped] value) -> String
  def output_client_overrides: (String main_locale) -> String
  def slice_override_fallback!: (Hash[String, String] values, Array[String] keys) -> Hash[String, String]
end
''')
        entry = self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "client_override_context"\nCategoryCacheBootstrap.configure('))
        original = self.path/'messageformat_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "client_override_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        observations = []
        for name in ('native', 'compat', 'compat-original'):
            rows = [json.loads(line.split(' ', 1)[1]) for line in (self.path/(name+'.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            items = [row['template_prefix']['client_overrides'] for row in rows]
            assert [item['builds'] for item in items] == [1, 2], (name, items)
            assert all(item['bytes'] == 0 and item['nil_entry_present'] and not item['digest_cached'] and item['checks'] == item['builds'] for item in items)
            observations.append(items)
        assert observations[0] == observations[1] == observations[2]
        controls = {}
        self.env['FIDELITY_OVERRIDE_FAULT'] = 'skip-empty-retry'
        try:
            for runtime, argv in (('native', [self.path/'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path/'compat/entry.rb'])):
                name = runtime+'-override-skip-empty-retry'
                code, _ = self.command(name, argv, check=False, timeout=120)
                assert code != 0 and 'empty override nil cache lifetime violated' in (self.path/(name+'.stderr')).read_text(), name
                lifecycle(self, name)
                assert all(self.evidence[key][name] for key in ('owned_cache_cleanup', 'owned_vm_source_cleanup', 'asset_lease_cleanup', 'owned_mf_source_cleanup'))
                controls[name] = {'returncode': code, 'all_fixtures_cleaned': True}
        finally:
            del self.env['FIDELITY_OVERRIDE_FAULT']
        self.evidence.update(actual_client_override_observations=observations[0], client_override_controls=controls, full_layout_completed=False)

    def command(self, name, argv, **kwargs):
        if name == 'native-compile':
            # Previous C phase was170.575s versus ~60s: improve part balance,
            # keep max4 compiler jobs and existing600s measurement window.
            argv = list(argv)
            argv.insert(1, '--split-parts=8')
        if name.startswith('compat'):
            tree = self.path/('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in OVERRIDE_FILES: shutil.copyfile(self.path/item, tree/item)
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ClientOverrideStageRun())
