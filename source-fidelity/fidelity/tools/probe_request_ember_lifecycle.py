#!/usr/bin/env python3
"""Bounded full-original/SAME/native lifecycle; unit fixtures NEVER request inputs."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
MANIFEST = Path('frontend/discourse/dist/manifest/manifest.json')

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    build = Path(tempfile.mkdtemp(prefix='request-ember-lifecycle-', dir=HERE / 'build'))
    evidence = {'status': 'FAILED', 'html_accepted': False}
    def command(name, argv, cwd=ROOT, check=True, timeout=180):
        result = subprocess.run([str(x) for x in argv], cwd=cwd, env=os.environ.copy(), capture_output=True, timeout=timeout)
        (build / (name + '.stdout')).write_bytes(result.stdout)
        (build / (name + '.stderr')).write_bytes(result.stderr)
        if check and result.returncode:
            raise RuntimeError(f'{name}: {result.returncode}; see {build}/{name}.stderr')
        return result
    try:
        command('generate', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_request_ember_assets.rb', build], ROOT / 'discourse')
        common = (HERE / 'test/request_ember_assets_observations.rb').read_text()
        shared = build / 'shared.rb'
        shared.write_text("require_relative 'request_ember_assets'\ndef new_request_ember_assets(root)\nRequestEmberAssets.new(root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV')))\nend\n" + common)
        original = build / 'original.rb'
        original.write_text("require_relative 'request_ember_assets'\nrequire_relative 'original_request_ember_assets'\ndef new_request_ember_assets(root)\nOriginalRequestEmberAssets.new(root, nil)\nend\n" + common)
        genuine = HERE / 'build/recovery24-frontend/source'
        roots = [genuine, ROOT / 'discourse']
        fixture_names = []
        # All fixture manifest bytes are copied from the real build, not a
        # fabricated graph. The actual build is never modified.
        payload = (genuine / MANIFEST).read_bytes()
        for label, manifest, status in (
            ('missing', None, None), ('malformed', b'{bad-json', None),
            ('build-error', payload, {'status': 'error', 'error': {'message': '<build & failed>', 'messageHtml': '&lt;build &amp; failed&gt;'}}),
            ('crashed', payload, {'status': 'crashed', 'error': {'message': 'builder crashed'}}),
            ('completed', payload, {'status': 'ok'}),
            ('malformed-status', payload, b'{bad-json'), ('nonhash-status', payload, []),
            ('live-build', payload, {'status': 'building'}),
            ('live-pid', payload, {'status': 'ok', 'pid': os.getpid()}),
            ('dead-pid', payload, {'status': 'ok', 'pid': 2147483647}),
        ):
            root = build / ('unit-only-' + label)
            (root / MANIFEST).parent.mkdir(parents=True)
            if manifest is not None: (root / MANIFEST).write_bytes(manifest)
            if status is not None:
                (root / MANIFEST).with_name('build.json').write_bytes(status if isinstance(status, bytes) else json.dumps(status).encode())
            roots.append(root)
            fixture_names.append(label)
        roots.append(genuine)
        expected = command('original', ['bundle', 'exec', 'ruby', original, *roots], ROOT / 'discourse').stdout
        def comparable(output):
            records = [json.loads(x) for x in output.splitlines()]
            # CRuby's locked json gem and the native JSON parser have distinct
            # diagnostic prose. Preserve raw messages; compare the same raised
            # ParserError type and require a real nonempty diagnostic.
            for row in records:
                if row.get('error') == 'ParserError':
                    assert row['message']
                    row['message'] = '[platform JSON parser diagnostic; raw retained]'
            return records
        assert comparable(command('shared', ['bundle', 'exec', 'ruby', shared, *roots], ROOT / 'discourse').stdout) == comparable(expected)
        command('compile', [ROOT / 'spinel/spinel', '--jobs=4', '--int-overflow=promote', shared, '-o', build / 'probe'], timeout=300)
        assert comparable(command('native', [build / 'probe', *roots]).stdout) == comparable(expected)
        outputs = [json.loads(x) for x in expected.splitlines()]
        assert outputs[0] == outputs[-1] and outputs[0]['imports'] and outputs[0]['chunks']
        assert outputs[1]['error'] == 'BuildError' and 'No frontend build found' in outputs[1]['message']
        by_label = dict(zip(fixture_names, outputs[2:-1]))
        assert by_label['malformed']['error'] == 'ParserError'
        assert by_label['build-error']['message'] == '<build & failed>'
        assert by_label['live-build']['message'] == 'unsupported live asset build profile'
        assert by_label['dead-pid']['error'] == 'BuildError'
        assert by_label['live-pid']['message'] == 'unsupported live asset build profile'
        lifetime_root = build / 'unit-only-cache-lifetime'
        (lifetime_root / MANIFEST).parent.mkdir(parents=True)
        changed = json.loads(payload)
        del changed['importMap'][next(iter(changed['importMap']))]
        replacement = build / 'unit-derived-manifest-change.json'
        replacement.write_text(json.dumps(changed))
        lifetime_outputs = []
        os.environ['FIDELITY_UNIT_ASSET_REPLACEMENT'] = str(replacement)
        try:
            for label, argv in (('original-live-reset', ['bundle', 'exec', 'ruby', original, lifetime_root]), ('shared-live-reset', ['bundle', 'exec', 'ruby', shared, lifetime_root]), ('native-live-reset', [build / 'probe', lifetime_root])):
                (lifetime_root / MANIFEST).write_bytes(payload)
                lifetime_outputs.append(command(label, argv, ROOT / 'discourse').stdout)
        finally:
            del os.environ['FIDELITY_UNIT_ASSET_REPLACEMENT']
        assert lifetime_outputs[0] == lifetime_outputs[1] == lifetime_outputs[2]
        # A real malformed-cache-lifetime mutant must fail both runtimes, not
        # merely produce a different recorded observation.
        mutant = build / 'unit-reset-mutant'
        mutant.mkdir()
        code = (build / 'request_ember_assets.rb').read_text()
        assert code.count('def reset; clear_cache!; end') == 1
        (mutant / 'request_ember_assets.rb').write_text(code.replace('def reset; clear_cache!; end', 'def reset; nil; end'))
        (mutant / 'request_ember_assets.rbs').write_bytes((build / 'request_ember_assets.rbs').read_bytes())
        (mutant / 'shared.rb').write_text(shared.read_text())
        command('mutant-compile', [ROOT / 'spinel/spinel', '--jobs=4', '--int-overflow=promote', mutant / 'shared.rb', '-o', mutant / 'probe'], timeout=300)
        mutation_controls = {}
        for label, argv in (('shared-reset-mutant', ['bundle', 'exec', 'ruby', mutant / 'shared.rb', genuine]), ('native-reset-mutant', [mutant / 'probe', genuine])):
            result = command(label, argv, ROOT / 'discourse', check=False)
            assert result.returncode != 0 and b'asset request state leaked' in result.stderr
            assert b'FIDELITY_ASSET_UNIT_MUTANT_CLEANUP reset_failed_but_state_cleared' in result.stdout
            mutation_controls[label] = {'returncode': result.returncode, 'expected': 'asset request state leaked', 'state_cleaned': True}
        evidence.update(status='PASS_SCOPED_ORIGINAL_SHARED_NATIVE_EMBER_LIFECYCLE', mutation_controls=mutation_controls, source=json.loads((build / 'ember-lifecycle-source-proof.json').read_text()), observations=outputs)
    finally:
        (build / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(build)

if __name__ == '__main__': main()
