#!/usr/bin/env python3
"""Actual cumulative import-map acquisition; never a full original Rails HTML."""
import json
import os
import shutil
from pathlib import Path
from asset_serving_capability import acquire
from probe_theme_array_stage import ThemeArrayStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

ASSET_FILES = ('request_ember_assets.rb', 'request_ember_assets.rbs', 'original_request_ember_assets.rb', 'original_request_asset_boot.rb',
               'request_asset_paths_source.rb', 'request_asset_helpers.rb', 'original_request_asset_helpers.rb',
               'request_asset_context.rb', 'request_asset_original_context.rb', 'request_asset_capability.rb')

class ImportMapAssetsStageRun(ThemeArrayStageRun):
    success_status = 'PASS_SCOPED_ACTUAL_IMPORTMAP_ASSET_ACQUISITION'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-request-ember-assets', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_request_ember_assets.rb', self.path], cwd=ROOT / 'discourse')
        self.command('generate-request-asset-helpers', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_request_asset_helpers.rb', self.path], cwd=ROOT / 'discourse')
        self.evidence['request_asset_source'] = json.loads((self.path / 'request-assets-source-proof.json').read_text())
        self.evidence['ember_lifecycle_source'] = json.loads((self.path / 'ember-lifecycle-source-proof.json').read_text())
        self.asset_provenance = acquire(ROOT, self.path / 'asset-serving-provenance.json')
        self.evidence['asset_serving_provenance'] = {k: v for k, v in self.asset_provenance.items() if k != 'files'}
        self.evidence['asset_serving_provenance']['file_count'] = len(self.asset_provenance['files'])
        self.evidence['asset_serving_provenance']['sha256'] = digest((self.path / 'asset-serving-provenance.json').read_bytes())

    def generate(self):
        super().generate()
        for name in ASSET_FILES:
            source = HERE / 'test' / name
            if source.exists(): shutil.copyfile(source, self.path / name)
        runtime = self.path / 'emitted/runtime/action_view/source_asset_paths.rb'
        runtime.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'roundhouse/runtime/ruby/action_view/source_asset_paths.rb', runtime)
        shutil.copyfile(ROOT / 'roundhouse/runtime/ruby/action_view/source_asset_paths.rbs', runtime.with_suffix('.rbs'))
        shutil.copyfile(self.path / 'request_ember_assets.rbs', self.path / 'emitted/runtime/request_ember_assets.rbs')
        proof_sha = digest((self.path / 'asset-serving-provenance.json').read_bytes())
        (self.path / 'request_asset_capability.rb').write_text('module RequestAssetCapability\nROOT = ' + json.dumps(self.asset_provenance['root']) + '\nPIN = ' + json.dumps(self.asset_provenance['pin']) + '\nPROVENANCE_SHA256 = ' + json.dumps(proof_sha) + '\nend\n')
        context = self.path / 'request_asset_context.rb'
        text = 'require_relative "request_asset_capability"\n' + context.read_text()
        text = text.replace('value = source_script_asset_path(script)', 'value = source_script_asset_path(script)\n    value += "#wrong-url" if ENV.fetch("FIDELITY_ASSET_FAULT", "") == "wrong-url"\n    raise "wrong acquired asset URL" unless settings.use_s3? || value == asset_paths.asset_path("#{script}.js")')
        text = text.replace('@asset_load_path = ActionView::SourceAssetLoadPath.new(RequestAssetSource.paths(@asset_source_root), RequestAssetSource.version(@asset_settings))', 'paths = RequestAssetSource.paths(@asset_source_root)\n    paths = paths.reject { |path| path.end_with?("/dist/assets") } if ENV.fetch("FIDELITY_ASSET_FAULT", "") == "wrong-load-path"\n    @asset_load_path = ActionView::SourceAssetLoadPath.new(paths, RequestAssetSource.version(@asset_settings))')
        text = text.replace('@request_assets.reset\n        raise', '@request_assets.reset unless ENV.fetch("FIDELITY_ASSET_FAULT", "") == "omitted-reset"\n        if !@request_assets.request_cache.nil?\n          @request_assets.reset\n          raise "asset request cache cleanup failed; recovered by real reset"\n        end\n        raise')
        context.write_text(text)
        entry = self.path / 'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "request_asset_context"\nCategoryCacheBootstrap.configure('))

    def verify_continuation(self):
        super().verify_continuation()
        manifest = json.loads((Path(self.asset_provenance['root']) / self.asset_provenance['manifest']).read_text())
        values = []
        for name in ('native', 'compat', 'compat-original'):
            records = [json.loads(line.split(' ', 1)[1]) for line in (self.path / (name + '.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            for record in records:
                view = record['template_prefix']
                result = json.loads(view['returned_import_map'])['imports']
                assert view['asset_request_reset'] and view['import_map_returned']
                assert all(view['asset_lifecycle'].values())
                assert len(result) == len(manifest['importMap']) and result
                for stable, real in manifest['importMap'].items():
                    logical = real.removeprefix('assets/').removesuffix('.js')
                    url = view['asset_urls'][logical]
                    key = url.replace(Path(real).name.removesuffix('.js'), Path(stable).name.removesuffix('.js'))
                    assert result[key] == url and url.endswith(real.removeprefix('assets/'))
                    assert (Path(self.asset_provenance['root']) / 'frontend/discourse/dist' / real).is_file()
                values.append(result)
        assert all(item == values[0] for item in values)
        controls = {}
        for fault, expected in (('wrong-owner', 'asset serving lease ownership'), ('wrong-root', 'wrong asset serving root'), ('stale-provenance', 'asset serving provenance identity'), ('wrong-load-path', 'was not found in the load path'), ('wrong-url', 'wrong acquired asset URL'), ('omitted-reset', 'asset request cache cleanup failed; recovered by real reset')):
            self.env['FIDELITY_ASSET_FAULT'] = fault
            for runtime, argv in (('native', [self.path / 'probe']), ('compat', ['bundle', 'exec', 'ruby', self.path / 'compat/entry.rb'])):
                name = runtime + '-asset-' + fault
                code, _ = self.command(name, argv, check=False, timeout=120)
                assert code != 0 and expected in (self.path / (name + '.stderr')).read_text(), name
                lifecycle(self, name)
                assert self.evidence['owned_cache_cleanup'][name] and self.evidence['owned_vm_source_cleanup'][name] and self.evidence['asset_lease_cleanup'][name]
                controls[name] = {'returncode': code, 'expected_error': expected, 'all_owned_fixtures_cleaned': True}
        del self.env['FIDELITY_ASSET_FAULT']
        self.evidence.update(asset_controls=controls, actual_import_map_returned=True, acquired_asset_imports=values[0],
                             serving_root_bound_explicitly=True, original_full_ember_assets_compared=True,
                             live_asset_build_or_watch_started=False, full_layout_completed=False)

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path / ('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in ASSET_FILES: shutil.copyfile(self.path / item, tree / item)
        if name == 'compat-original':
            # Load actual isolated framework BEFORE the lowered I18n exception
            # declarations, avoiding a superclass collision. No Rails app boot.
            argv = list(argv)
            position = [str(x) for x in argv].index('ruby') + 1
            argv[position:position] = ['-r' + str(self.path / 'original_request_asset_boot.rb')]
            entry = self.path / 'compat/entry-original.rb'
            entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "request_asset_original_context"\nCategoryCacheBootstrap.configure('))
        binary = str(self.path / 'probe')
        runtime = name.startswith('compat') or name != 'native-compile' and binary in [str(x) for x in argv]
        if runtime:
            lease = self.path / (name + '-asset-lease.json')
            fault = self.env.get('FIDELITY_ASSET_FAULT', '')
            lease_data = {'owner_pid': os.getpid(), 'root': self.asset_provenance['root'], 'provenance': str(self.path / 'asset-serving-provenance.json')}
            stale_provenance = self.path / (name + '-stale-provenance.json')
            if fault == 'wrong-owner': lease_data['owner_pid'] += 1
            if fault == 'wrong-root': lease_data['root'] = str(ROOT / 'discourse')
            if fault == 'stale-provenance':
                stale_provenance.write_text('{}')
                lease_data['provenance'] = str(stale_provenance)
            lease.write_text(json.dumps(lease_data))
            prior = self.env.get('FIDELITY_ASSET_LEASE')
            self.env['FIDELITY_ASSET_LEASE'] = str(lease)
            try:
                return super().command(name, argv, **kwargs)
            finally:
                if prior is None: self.env.pop('FIDELITY_ASSET_LEASE', None)
                else: self.env['FIDELITY_ASSET_LEASE'] = prior
                lease.unlink()
                if stale_provenance.exists(): stale_provenance.unlink()
                self.evidence.setdefault('asset_lease_cleanup', {})[name] = not lease.exists() and not stale_provenance.exists()
        return super().command(name, argv, **kwargs)

if __name__ == '__main__':
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ImportMapAssetsStageRun())
