#!/usr/bin/env python3
"""Explicit UNIT-only override formatting/mutation differential; never request input."""
import json
import os
import subprocess
import tempfile
from pathlib import Path
from verify import HERE, ROOT, digest


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    build = Path(tempfile.mkdtemp(prefix='client-override-unit-', dir=HERE/'build'))
    evidence = {'status': 'FAILED', 'unit_component_only': True, 'page_accepted': False}
    def command(name, argv, timeout=300):
        result = subprocess.run([str(x) for x in argv], cwd=ROOT/'discourse', capture_output=True, timeout=timeout)
        (build/(name+'.stdout')).write_bytes(result.stdout)
        (build/(name+'.stderr')).write_bytes(result.stderr)
        if result.returncode: raise RuntimeError(f'{name}: {result.returncode}; see {build}/{name}.stderr')
        return result.stdout
    try:
        # Generate afresh from immutable source; no canonical request graph or
        # observed SQL/result/script is copied into this UNIT input profile.
        command('generate-client', ['bundle', 'exec', 'ruby', HERE/'tools/generate_client_locale_source.rb', build])
        app = build/'unit-app'; (app/'app/models').mkdir(parents=True)
        (app/'app/models/translation_override.rb').write_text('class TranslationOverride\nend\n')
        (build/'request_extra_locale_source.rb').write_text("raise HtmlRenderingBoundary, 'actual main/MF locale scripts/preloads acquired; client override bundle acquisition pending'\n")
        command('generate-overrides', ['bundle', 'exec', 'ruby', HERE/'tools/generate_client_overrides_stage.rb', app, build])
        extractor = '''require 'prism'
root = ARGV.fetch(0)
[['original_client_locale_source.rb', [:output_client_overrides], 'original-method.rb'], ['request_client_locale_source.rb', [:output_client_overrides, :slice_override_fallback!, :client_override_json], 'shared-methods.rb']].each do |file, names, target|
  nodes = []
  visit = lambda do |n|
    nodes << n if n.is_a?(Prism::DefNode) && names.include?(n.name)
    n.compact_child_nodes.each { |c| visit.call(c) }
  end
  visit.call(Prism.parse_file(File.join(root, file)).value)
  raise 'unit source method ambiguity' unless nodes.size == names.size
  File.write(File.join(root, target), nodes.map(&:slice).join("\\n"))
end
'''
        command('extract-methods', ['bundle', 'exec', 'ruby', '-e', extractor, build])
        # These synthetic rows exercise source formatting only. They NEVER
        # masquerade as live TranslationOverride data or enter the page probe.
        inputs = '''module UnitOverrides
  class << self; attr_accessor :case_id; end
  def self.chain
    case case_id
    when 4 then [:fr, :en, :de]
    else [:fr, :en]
    end
  end
  def self.rows(locale)
    case case_id
    when 0 then []
    when 1 then locale == :fr ? [["js.main", "bonjour"]] : []
    when 2 then locale == :fr ? [["js.main", "<script>&\\u2028\\u2029"]] : [["js.main", "fallback"], ["js.other", "other"]]
    when 3 then locale == :en ? [["js.only", "fallback only"]] : []
    else [["js.shared", locale.to_s], ["js.unique." + locale.to_s, "value"]]
    end
  end
end
class UnitOverrideRows
  def initialize(locale); @locale = locale.to_sym; end
  def pluck(*names)
    raise 'unit pluck shape changed' unless names == [:translation_key, :value]
    UnitOverrides.rows(@locale)
  end
end
class TranslationOverride
  def self.client_locales(locale); UnitOverrideRows.new(locale); end
end
'''
        common = '''observations = []
[0, 1, 2, 3, 4].each do |id|
  UnitOverrides.case_id = id
  begin
    script = unit_output
    observations << {case_id: id, script: script}
  rescue StandardError => error
    observations << {case_id: id, error: error.class.to_s}
  end
end
values = {"keep" => "a", "remove" => "b"}
same = values
removed = unit_slice(values, ["keep"])
observations << {case_id: 5, removed: removed, kept: values, identity_preserved: values.equal?(same)}
puts JSON.generate(observations)
'''
        original = '''require 'json'
require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/enumerable'
require 'active_support/core_ext/object/json'
require 'active_support/core_ext/hash/slice'
''' + inputs + '''module I18n
  def self.fallbacks; UnitFallbacks; end
end
module UnitFallbacks
  def self.[](locale); UnitOverrides.chain; end
end
module OriginalOverrides
''' + (build/'original-method.rb').read_text() + '''
end
def unit_output; OriginalOverrides.output_client_overrides('fr'); end
def unit_slice(values, keys); values.slice!(*keys); end
''' + common
        shared = '''require 'json'
require_relative ''' + json.dumps(os.path.relpath(ROOT/'roundhouse/runtime/ruby/active_support_ext.rb', build)) + '''
require_relative ''' + json.dumps(os.path.relpath(ROOT/'roundhouse/runtime/ruby/json_builder.rb', build)) + '\n' + inputs + '''class UnitOverridesHelper
  def fallbacks(locale); UnitOverrides.chain; end
  def client_json(value); JsonBuilder.escape_html_entities(JSON.generate(value)); end
''' + (build/'shared-methods.rb').read_text() + '''
end
def unit_output; UnitOverridesHelper.new.output_client_overrides('fr'); end
def unit_slice(values, keys); UnitOverridesHelper.new.slice_override_fallback!(values, keys); end
''' + common
        (build/'original.rb').write_text(original); (build/'shared.rb').write_text(shared)
        outputs = [command('original', ['bundle', 'exec', 'ruby', build/'original.rb']), command('shared', ['bundle', 'exec', 'ruby', build/'shared.rb'])]
        assert outputs[0] == outputs[1]
        command('compile', [ROOT/'spinel/spinel', '--jobs=4', '--int-overflow=promote', build/'shared.rb', '-o', build/'probe'])
        outputs.append(command('native', [build/'probe']))
        assert outputs[0] == outputs[2]
        rows = json.loads(outputs[0])
        assert rows[0]['script'] == '' and all('script' in row and row['script'] for row in rows[1:4])
        assert '\\u003cscript\\u003e' in rows[2]['script'] and 'fallback only' in rows[3]['script']
        assert '\\u2028' in rows[2]['script'] and '\\u2029' in rows[2]['script']
        assert rows[4] == {'case_id': 4, 'error': 'NoMethodError'}  # Original three-locale reduce failure retained.
        assert rows[5] == {'case_id': 5, 'removed': {'remove': 'b'}, 'kept': {'keep': 'a'}, 'identity_preserved': True}
        # Wrong removed-map return must fail exact original comparison even
        # though the in-place mutation and two-locale script still look right.
        assert shared.count('    omitted\n') == 1
        mutant = shared.replace('    omitted\n', '    kept\n')
        (build/'mutant.rb').write_text(mutant)
        command('mutant-compile', [ROOT/'spinel/spinel', '--jobs=4', '--int-overflow=promote', build/'mutant.rb', '-o', build/'mutant'])
        mutation_outputs = [command('mutant-shared', ['bundle', 'exec', 'ruby', build/'mutant.rb']), command('mutant-native', [build/'mutant'])]
        assert mutation_outputs[0] == mutation_outputs[1] and all(value != outputs[0] for value in mutation_outputs)
        evidence['wrong_slice_return_mutation_rejected'] = True
        evidence.update(status='PASS_UNIT_CLIENT_OVERRIDE_OUTPUT', source=json.loads((build/'client-overrides-source-proof.json').read_text()), observations=rows, shared_sha256=digest(shared.encode()))
    finally:
        (build/'evidence.json').write_text(json.dumps(evidence, indent=2)+'\n')
        print(build)

if __name__ == '__main__': main()
