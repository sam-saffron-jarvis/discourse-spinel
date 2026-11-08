#!/usr/bin/env python3
"""Ruby-free original MessageFormat VM component; explicit UNIT inputs, NOT page."""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from verify import HERE, ROOT, digest

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    build = Path(tempfile.mkdtemp(prefix='messageformat-vm-', dir=HERE / 'build'))
    evidence = {'status': 'FAILED', 'page_accepted': False, 'unit_component_only': True, 'commands': []}
    env = os.environ.copy()
    def command(name, argv, check=True, timeout=120):
        result = subprocess.run([str(x) for x in argv], cwd=ROOT / 'discourse', env=env, capture_output=True, timeout=timeout)
        (build / (name+'.stdout')).write_bytes(result.stdout); (build / (name+'.stderr')).write_bytes(result.stderr)
        evidence['commands'].append({'name': name, 'returncode': result.returncode})
        if check and result.returncode: raise RuntimeError(f'{name}: {result.returncode}; see {build}/{name}.stderr')
        return result
    try:
        adapter_sha = digest((HERE / 'test/layout_asset_processor_native.cc').read_bytes())
        matching = []
        for file in (HERE / 'build').glob('native-asset-vm-*/evidence.json'):
            proof = json.loads(file.read_text())
            if proof.get('status') == 'PASS_SCOPED_RUBY_FREE_ORIGINAL_V8_VERSION_COMPONENT' and proof.get('adapter_sha256') == adapter_sha:
                matching.append((file.stat().st_mtime, proof))
        bridge = max(matching, key=lambda item: item[0])[1]
        library = bridge['native_library']; assert digest(Path(library['path']).read_bytes()) == library['sha256']
        env.update(FIDELITY_SOURCE_OWNER_PID=str(os.getpid()), FIDELITY_VM_LIBRARY=library['path'], FIDELITY_VM_LIBRARY_SHA256=library['sha256'])
        source_root = build / 'owned-source'
        command('materialize-source', ['bundle', 'exec', 'ruby', HERE / 'tools/materialize_messageformat_source.rb', source_root])
        env['FIDELITY_MF_SOURCE_ROOT'] = str(source_root)
        cached = [p for p in (ROOT / 'discourse/tmp/asset-processor').glob('asset-processor-*.js') if digest(p.read_bytes()) == bridge['original_inspection']['bundle_sha256']]
        assert len(cached) == 1
        env.update(FIDELITY_LAYOUT_SOURCE=str(cached[0]), FIDELITY_LAYOUT_SOURCE_SHA256=digest(cached[0].read_bytes()), FIDELITY_VM_SINGLE_THREADED='1' if bridge['configured_single_threaded'] else '0')
        fixtures = [
            {'name': 'unit-simple', 'locales': ['en'], 'messages': {'en': {'greeting': 'Hello {NAME}', 'count': '{N, plural, one {one item} other {# items}}'}}, 'strict': False},
            {'name': 'unit-multilingual', 'locales': ['en', 'fr'], 'messages': {'en': {'v': '{N, plural, one {one} other {#}}'}, 'fr': {'v': '{N, plural, one {un} other {#}}'}}, 'strict': False},
            {'name': 'unit-bad-pattern', 'locales': ['en'], 'messages': {'en': {'v': '{N, plural, one {broken}'}}, 'strict': False},
            {'name': 'unit-good-after-error', 'locales': ['en'], 'messages': {'en': {'v': 'Still healthy {NAME}'}}, 'strict': False},
            {'name': 'unit-single-string-api', 'locales': 'en', 'messages': 'Direct pattern {NAME}', 'strict': False},
        ]
        (build / 'unit-inputs.json').write_text(json.dumps(fixtures));env['FIDELITY_UNIT_MF_INPUTS']=str(build/'unit-inputs.json')
        common = '''require 'json'
require 'digest'
root = ENV.fetch('FIDELITY_MF_SOURCE_ROOT')
lease = JSON.parse(File.read(File.join(root, 'source-lease.json')))
raise 'MF source owner' unless lease['owner_pid'] == ENV.fetch('FIDELITY_SOURCE_OWNER_PID').to_i && lease['generated_result_supplied'] == false
lease['files'].each { |name, sha| raise 'MF source bytes' unless !name.include?('..') && Digest::SHA256.file(File.join(root,name)).hexdigest == sha }
sources = File.read(File.join(root, 'source-packet.json'))
raise 'native library changed' unless Digest::SHA256.file(ENV.fetch('FIDELITY_VM_LIBRARY')).hexdigest == ENV.fetch('FIDELITY_VM_LIBRARY_SHA256')
layout = File.read(ENV.fetch('FIDELITY_LAYOUT_SOURCE'))
raise 'layout source changed' unless Digest::SHA256.hexdigest(layout) == ENV.fetch('FIDELITY_LAYOUT_SOURCE_SHA256')
backend = LayoutAssetProcessorBackend.new(ENV.fetch('FIDELITY_VM_LIBRARY'))
threads_before = Dir.entries('/proc/self/task').reject { |n| n == '.' || n == '..' }.size
begin
  backend.start(layout, ENV.fetch('FIDELITY_VM_SINGLE_THREADED') == '1')
  original_version = backend.ember_version
  JSON.parse(File.read(ENV.fetch('FIDELITY_UNIT_MF_INPUTS'))).each do |item|
    begin
      value = compile_mf(backend, sources, item['locales'], item['messages'], item['strict'])
      raise 'MF result not String' unless value.is_a?(String) && !value.empty?
      puts 'FIDELITY_MF_RESULT ' + JSON.generate({name: item['name'], sha256: Digest::SHA256.hexdigest(value), bytes: value.bytesize})
    rescue StandardError => error
      raise unless item['name'] == 'unit-bad-pattern'
      puts 'FIDELITY_MF_RESULT ' + JSON.generate({name: item['name'], error: true})
    end
    raise 'MF damaged retained original asset VM' unless backend.ember_version == original_version
  end
ensure
  backend.close
end
threads_after = Dir.entries('/proc/self/task').reject { |n| n == '.' || n == '..' }.size
raise 'MF/asset VM OS threads leaked' unless threads_after == threads_before
puts 'FIDELITY_MF_THREADS_CLEAN 1'
'''
        shutil.copyfile(HERE / 'test/layout_asset_processor_backend.rb', build / 'native_backend.rb')
        shutil.copyfile(HERE / 'test/layout_asset_processor_cruby_backend.rb', build / 'cruby_backend.rb')
        native = build / 'native.rb'
        native.write_text("require_relative 'native_backend'\ndef compile_mf(backend, sources, locales, messages, strict)\nbackend.compile_messageformat(sources, JSON.generate(locales), JSON.generate(messages), strict)\nend\n" + common)
        original = build / 'original.rb'
        original.write_text("require_relative 'cruby_backend'\nrequire 'messageformat'\ndef compile_mf(backend, sources, locales, messages, strict)\ncompiler = MessageFormat::Compiler.new(locales, messages, strict: strict)\nbegin; compiler.compile; ensure; compiler.context.dispose; end\nend\n" + common)
        shared = build / 'shared.rb'
        shared.write_text("require_relative 'cruby_backend'\ndef compile_mf(backend, sources, locales, messages, strict)\nbackend.compile_messageformat(sources, JSON.generate(locales), JSON.generate(messages), strict)\nend\n" + common)
        command('compile', [ROOT / 'spinel/spinel', '--jobs=4', '--int-overflow=promote', native, '-o', build/'probe'], timeout=240)
        outputs = []
        for name, argv in (('native', ['strace','-f','-e','trace=execve,connect','-o',build/'native.trace',build/'probe']), ('shared', ['bundle','exec','ruby',shared]), ('original', ['bundle','exec','ruby',original])):
            result = command(name, argv)
            assert b'FIDELITY_MF_THREADS_CLEAN 1' in result.stdout
            outputs.append([json.loads(line.split(b' ',1)[1]) for line in result.stdout.splitlines() if line.startswith(b'FIDELITY_MF_RESULT ')])
        assert outputs[0] == outputs[1] == outputs[2]
        assert len(outputs[0]) == 5 and outputs[0][2]['error'] is True
        trace = (build/'native.trace').read_text();assert trace.count('execve(')==1 and 'connect(' not in trace
        evidence.update(status='PASS_SCOPED_ORIGINAL_NATIVE_MESSAGEFORMAT_VM', observations=outputs[0], native_library=library, no_ruby_child_or_network=True, separate_mf_context_on_existing_platform=True)
    finally:
        if (build/'owned-source').exists(): shutil.rmtree(build/'owned-source')
        evidence['source_fixture_cleaned'] = not (build/'owned-source').exists()
        (build/'evidence.json').write_text(json.dumps(evidence,indent=2)+'\n'); print(build)

if __name__ == '__main__': main()
