# frozen_string_literal: true
# XML engine component proof, NOT SVG bundle/request/page acceptance.
require 'json'
require 'digest'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'prism'
require 'nokogiri'
require 'active_support/core_ext/object/blank'
root = File.expand_path('../..', __dir__)
build = Dir.mktmpdir('native-svg-xml-', File.join(root, 'fidelity/build'))
proof = {status: 'in_progress', scope: 'actual owned-source SVG DOM XML component only', page_accepted: false, svg_bundle_acquired: false, commands: []}
save = -> { File.write(File.join(build, 'evidence.json'), JSON.pretty_generate(proof) + "\n") }
command = lambda do |name, argv, environment = {}, timeout = 120|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  output = error = ''
  code = nil
  Open3.popen3(environment, *argv, chdir: root, pgroup: true) do |input, out, err, process|
    input.close
    readers = [Thread.new { out.read }, Thread.new { err.read }]
    begin
      if process.join(timeout)
        code = process.value.exitstatus
      else
        Process.kill('KILL', -process.pid)
        process.join
        code = 124
      end
    ensure
      unless process.join(0)
        Process.kill('KILL', -process.pid)
        process.join
      end
      output, error = readers.map(&:value)
    end
  end
  File.write(File.join(build, name + '.stdout'), output)
  File.write(File.join(build, name + '.stderr'), error)
  proof[:commands] << {name: name, argv: argv, returncode: code, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3), timeout: timeout}
  save.call
  raise "SVG XML #{name} failed #{code}: #{error[-2000..]}" unless code == 0
  output
end
begin
  pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:lib/svg_sprite.rb")
  raise 'XML source pin changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/lib/svg_sprite.rb'))
  owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
  methods = owner.body.body.grep(Prism::DefNode).select { |node| %i[symbols_for prepare_symbol].include?(node.name) }
  raise 'XML source methods changed' unless methods.size == 2
  Object.class_eval("module OriginalSvgXmlComponent\n#{methods.map(&:slice).join("\n")}\nend")
  proof[:original_source] = {pin: pin, source_sha256: Digest::SHA256.hexdigest(source), methods: methods.to_h { |node| [node.name, Digest::SHA256.hexdigest(node.slice)] }}
  backend_path = File.join(root, 'fidelity/test/svg_xml_backend.rb')
  native_path = File.join(root, 'fidelity/test/svg_xml_native.cc')
  probe_path = File.join(root, 'fidelity/test/svg_xml_component.rb')
  proof[:adapter_sha256] = Digest::SHA256.file(backend_path).hexdigest
  proof[:native_source_sha256] = Digest::SHA256.file(native_path).hexdigest
  proof[:probe_sha256] = Digest::SHA256.file(probe_path).hexdigest
  flags = command.call('pkg-config', ['pkg-config', '--cflags', '--libs', 'libxml-2.0']).split
  proof[:xml_pkg_version] = command.call('pkg-version', ['pkg-config', '--modversion', 'libxml-2.0']).strip
  library = File.join(build, 'libowned_svg_xml.so')
  command.call('compile-library', ['clang++', '-std=c++20', '-O1', '-fPIC', '-shared', native_path, *flags, '-o', library])
  dependencies = command.call('library-dependencies', ['ldd', library])
  raise 'XML native library linked Ruby' if dependencies.match?(/libruby|libpython|mini_racer/)
  proof[:library_dependencies] = dependencies
  xml_library = dependencies[/libxml2[^\s]*\s+=>\s+(\S+)/, 1]
  raise 'XML engine not linked actual libxml2' unless xml_library && File.file?(xml_library)
  proof[:system_libxml] = {path: File.realpath(xml_library), sha256: Digest::SHA256.file(xml_library).hexdigest}
  proof[:native_library] = {path: library, sha256: Digest::SHA256.file(library).hexdigest}
  # Expose already installed Fiddle to the unchanged application bundle. No gem
  # installation, original Gemfile/lock edit, or alternate engine result input.
  fiddle = JSON.parse(command.call('installed-fiddle', ['ruby', '-rjson', '-rfiddle', '-e', 'puts JSON.generate({version: Fiddle::VERSION, files: $LOADED_FEATURES.grep(/fiddle(?:\\.rb|\\.so)$/)})'], {'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil, 'GEM_HOME' => nil, 'GEM_PATH' => nil, 'BUNDLE_BIN_PATH' => nil}))
  raise 'unexpected installed Fiddle' unless fiddle['version'] == '1.1.8' && fiddle['files'].size == 2
  proof[:fiddle] = {version: fiddle['version'], files: fiddle['files'].to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }}
  ruby_lib = fiddle['files'].map { |path| File.dirname(path) }.uniq.join(File::PATH_SEPARATOR)
  ruby_lib += File::PATH_SEPARATOR + ENV['RUBYLIB'] if ENV['RUBYLIB'] && !ENV['RUBYLIB'].empty?
  serving = File.realpath(File.join(root, 'fidelity/build/recovery24-frontend/source'))
  files = Dir.glob(File.join(serving, 'vendor/assets/svg-icons/**/*.svg')).to_h do |path|
    relative = path.delete_prefix(serving + '/')
    original, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{relative}")
    raise "SVG XML asset changed #{relative}" unless status.success? && original.b == File.binread(path)
    [relative, Digest::SHA256.hexdigest(original)]
  end
  raise 'SVG actual source file set empty' if files.empty?
  manifest = {root: serving, files: files, library: library, library_sha256: Digest::SHA256.file(library).hexdigest}
  manifest_path = File.join(build, 'source-manifest.json')
  File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
  proof[:source_inputs] = manifest
  %w[svg_xml_backend.rb svg_xml_component.rb].each { |file| FileUtils.copy_file(File.join(root, 'fidelity/test', file), File.join(build, file)) }
  environment = {'FIDELITY_SVG_XML_SOURCE_MANIFEST' => manifest_path, 'BUNDLE_GEMFILE' => File.join(root, 'discourse/Gemfile'), 'RUBYLIB' => ruby_lib}
  shared = command.call('shared-cruby', ['bundle', 'exec', 'ruby', '--enable-frozen-string-literal', File.join(build, 'svg_xml_component.rb')], environment)
  record = JSON.parse(shared.lines.find { |line| line.start_with?('FIDELITY_SVG_XML_COMPONENT ') }.split(' ', 2)[1])
  reference = {}
  files.each do |relative, _|
    path = File.join(serving, relative)
    value = OriginalSvgXmlComponent.symbols_for(File.basename(path, '.svg'), File.read(path), strict: true)
    reference[relative] = {keys: value.keys, count: value.size, sha256: Digest::SHA256.hexdigest(JSON.generate(value))}
  end
  # Read the labelled UNIT vector literals from the one shared test caller.
  tree = Prism.parse_file(probe_path).value.statements.body
  cases_node = tree.grep(Prism::LocalVariableWriteNode).find { |node| node.name == :cases }
  loose_node = tree.grep(Prism::LocalVariableWriteNode).find { |node| node.name == :loose }
  cases = Object.class_eval(cases_node.value.slice)
  loose = Object.class_eval(loose_node.value.slice)
  unit_reference = cases.to_h do |name, xml|
    value = OriginalSvgXmlComponent.symbols_for(name, xml, strict: true)
    [name, {keys: value.keys, sha256: Digest::SHA256.hexdigest(JSON.generate(value))}]
  end
  value = OriginalSvgXmlComponent.symbols_for('loose', loose, strict: false)
  unit_reference['loose'] = {keys: value.keys, sha256: Digest::SHA256.hexdigest(JSON.generate(value))}
  expected = JSON.parse(JSON.generate({files: reference, unit: unit_reference}))
  proof[:raw_nokogiri_reference] = {version: Nokogiri::VERSION_INFO, files: reference, unit: unit_reference}
  raise 'SVG actual XML DOM symbols differ from raw Nokogiri' unless record['files'] == expected['files'] && record['unit'] == expected['unit']
  native = File.join(build, 'probe')
  command.call('native-compile', [File.join(root, 'spinel/spinel'), '--timing', '--cc=clang', '--jobs=4', File.join(build, 'svg_xml_component.rb'), '-o', native], {}, 120)
  output = command.call('native', ['strace', '-f', '-e', 'trace=execve,connect', '-o', File.join(build, 'native.trace'), native], environment)
  native_record = JSON.parse(output.lines.find { |line| line.start_with?('FIDELITY_SVG_XML_COMPONENT ') }.split(' ', 2)[1])
  raise 'SVG XML native/shared component mismatch' unless native_record == record
  trace = File.read(File.join(build, 'native.trace'))
  raise 'SVG XML component spawned process or connected' unless trace.scan('execve(').size == 1 && !trace.include?('connect(')
  raise 'SVG XML component cleanup/negative failure' unless record['active_documents'] == 0 && record['controls'].size == 4 && record['controls'].values.all? { |value| value['refused'] && value['documents_freed'] }
  proof.merge!(status: 'PASS_SCOPED_RUBY_FREE_SVG_XML_SYMBOLS_COMPONENT', observed: record, same_driver_on_native_and_shared: true, raw_original_nokogiri_compared: true, native_spawn_or_connect: false, source_engine_versions_differ: true)
rescue Exception => error
  proof[:error] = "#{error.class}: #{error.message}"
  raise
ensure
  save.call
  puts build
end
