#!/usr/bin/env python3
"""Read-only original/shared/native client-locale source component; NOT request input."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent

def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    build = Path(tempfile.mkdtemp(prefix='client-locale-source-', dir=HERE / 'build'))
    evidence = {'status': 'FAILED', 'page_accepted': False, 'unit_component_only': True}
    def command(name, argv, timeout=300):
        result = subprocess.run([str(x) for x in argv], cwd=ROOT / 'discourse', env={**os.environ, 'RAILS_ENV': 'development'}, capture_output=True, timeout=timeout)
        (build / (name + '.stdout')).write_bytes(result.stdout)
        (build / (name + '.stderr')).write_bytes(result.stderr)
        if result.returncode: raise RuntimeError(f'{name}: {result.returncode}; see {build}/{name}.stderr')
        return result.stdout
    try:
        command('generate-environment', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_request_ember_assets.rb', build])
        command('generate', ['bundle', 'exec', 'ruby', HERE / 'tools/generate_client_locale_source.rb', build])
        common = '''require 'digest'
root = ARGV.shift
ARGV.each do |locale|
  source = new_client_locale_source(root)
  I18n.locale = locale.to_sym
  value = source.output_locale(locale)
  raise 'client JS result not String' unless value.is_a?(String) && value.include?('localeData.translations = ')
  File.write(File.join(ENV.fetch('FIDELITY_COMPONENT_OUTPUT'), locale + '.js'), value)
  puts JSON.generate({locale: locale, bytes: value.bytesize, sha256: Digest::SHA256.hexdigest(value)})
end
'''
        # UNIT I18n scope driver only; the application uses its existing live
        # I18n runtime. It supplies locale choice, never translations/JS/digests.
        shared = build / 'shared.rb'
        shared.write_text('''require 'json'
require_relative 'request_ember_assets'
require_relative 'client_locale_registry'
require_relative ''' + json.dumps(os.path.relpath(ROOT / 'roundhouse/runtime/ruby/active_support_ext.rb', build)) + '''
require_relative ''' + json.dumps(os.path.relpath(ROOT / 'roundhouse/runtime/ruby/json_builder.rb', build)) + '''
module I18n
  class << self; attr_accessor :locale; end
  def self.enter_locale(locale)
    previous = self.locale
    self.locale = locale
    previous
  end
  def self.leave_locale(previous); self.locale = previous; end
end
require_relative 'request_client_locale_source'
def new_client_locale_source(root)
  RequestClientLocaleSource.new(root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV')))
end
''' + common)
        original = build / 'original.rb'
        original.write_text('''require 'yaml'
require 'json'
require 'set'
require 'pathname'
require 'active_support'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/json'
require 'active_support/core_ext/string/inflections'
require 'active_support/environment_inquirer'
require 'i18n'
require_relative 'client_locale_registry'
module Rails
  class << self; attr_accessor :root; end
  def self.env; ActiveSupport::EnvironmentInquirer.new(ENV.fetch('RAILS_ENV')); end
end
module VendoredAssets
  def self.path(relative); Rails.root.join('vendor/runtime_node_modules', relative); end
end
require_relative 'original_client_locale_bindings'
require ''' + json.dumps(str(ROOT / 'discourse/lib/i18n/backend/fallback_locale_list.rb')) + '''
I18n.fallbacks = I18n::Backend::FallbackLocaleList.new
require_relative 'original_client_locale_source'
def new_client_locale_source(root)
  Rails.root = Pathname.new(root)
  I18n.backend.load_translations(*%w[en fr].map { |locale| Rails.root.join("config/locales/server.#{locale}.yml").to_s })
  OriginalClientLocaleSource
end
''' + common)
        built = HERE / 'build/recovery24-frontend/source'
        outputs = []
        for name, argv in (('original', ['bundle', 'exec', 'ruby', original]), ('shared', ['bundle', 'exec', 'ruby', shared])):
            directory = build / (name + '-outputs'); directory.mkdir()
            os.environ['FIDELITY_COMPONENT_OUTPUT'] = str(directory)
            outputs.append(command(name, [*argv, built, 'en', 'fr']))
        assert outputs[0] == outputs[1]
        command('compile', [ROOT / 'spinel/spinel', '--jobs=4', '--int-overflow=promote', shared, '-o', build / 'probe'])
        directory = build / 'native-outputs'; directory.mkdir()
        os.environ['FIDELITY_COMPONENT_OUTPUT'] = str(directory)
        outputs.append(command('native', [build / 'probe', built, 'en', 'fr']))
        assert outputs[0] == outputs[2]
        for locale in ('en', 'fr'):
            assert (build / 'original-outputs' / (locale+'.js')).read_bytes() == (directory / (locale+'.js')).read_bytes()
        # Mutation deliberately omits required _MF removal. It must be
        # rejected by exact original output comparison, not accepted as JS.
        mutant = build / 'unit-no-strip-mutant'
        mutant.mkdir()
        for name in ('request_ember_assets.rb', 'request_ember_assets.rbs', 'client_locale_registry.rb', 'request_client_locale_source.rbs'):
            (mutant / name).write_bytes((build / name).read_bytes())
        code = (build / 'request_client_locale_source.rb').read_text()
        anchor = '\n          hash.delete(key)\n'
        assert code.count(anchor) == 1
        (mutant / 'request_client_locale_source.rb').write_text(code.replace(anchor, '\n          nil\n'))
        script = shared.read_text().replace(os.path.relpath(ROOT / 'roundhouse/runtime/ruby/active_support_ext.rb', build), os.path.relpath(ROOT / 'roundhouse/runtime/ruby/active_support_ext.rb', mutant)).replace(os.path.relpath(ROOT / 'roundhouse/runtime/ruby/json_builder.rb', build), os.path.relpath(ROOT / 'roundhouse/runtime/ruby/json_builder.rb', mutant))
        (mutant / 'shared.rb').write_text(script)
        command('mutant-compile', [ROOT / 'spinel/spinel', '--jobs=4', '--int-overflow=promote', mutant / 'shared.rb', '-o', mutant / 'probe'])
        mutation_outputs = []
        for name, argv in (('shared-no-strip-mutant', ['bundle', 'exec', 'ruby', mutant / 'shared.rb']), ('native-no-strip-mutant', [mutant / 'probe'])):
            directory = build / (name + '-outputs'); directory.mkdir()
            os.environ['FIDELITY_COMPONENT_OUTPUT'] = str(directory)
            value = command(name, [*argv, built, 'en', 'fr'])
            assert value != outputs[0]
            mutation_outputs.append(value)
        assert mutation_outputs[0] == mutation_outputs[1]
        evidence.update(status='PASS_SOURCE_CLIENT_LOCALE_MAIN_COMPONENT', source=json.loads((build / 'client-locale-source-proof.json').read_text()), required_mf_removal_mutation_rejected_by_exact_output=True, observations=[json.loads(l) for l in outputs[0].splitlines()])
    finally:
        os.environ.pop('FIDELITY_COMPONENT_OUTPUT', None)
        (build / 'evidence.json').write_text(json.dumps(evidence, indent=2)+'\n')
        print(build)

if __name__ == '__main__': main()
