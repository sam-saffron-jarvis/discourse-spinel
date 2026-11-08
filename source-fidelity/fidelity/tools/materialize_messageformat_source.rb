# frozen_string_literal: true
# Materialize original locked MessageFormat SOURCES, never compiled JS/results.
require 'prism'
require 'json'
require 'digest'
require 'fileutils'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
FileUtils.mkdir_p(build)
metadata = {owner_pid: ENV.fetch('FIDELITY_SOURCE_OWNER_PID').to_i, files: {}, packages: [], generated_result_supplied: false}
source, package = FidelitySourcePackage.member(root, 'messageformat-wrapper-1.1.0', 'lib/messageformat.rb')
metadata[:packages] << package
wrappers = []
visit = lambda do |node|
  if node.is_a?(Prism::CallNode) && node.name == :eval
    argument = node.arguments.arguments.first
    if argument.is_a?(Prism::StringNode)
      wrappers << argument.unescaped
    elsif argument.is_a?(Prism::InterpolatedStringNode) && argument.parts.all? { |part| part.is_a?(Prism::StringNode) }
      wrappers << argument.parts.map(&:unescaped).join
    end
  end
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(source).value)
raise 'original MF wrapper changed' unless wrappers.size == 1 && wrappers.first.include?('function compileMessageFormat(locale, messages, strict)')
packet = []
%w[messageformat.js compilemodule.js].each do |name|
  bytes, package = FidelitySourcePackage.member(root, 'messageformat-wrapper-1.1.0', 'dist/' + name)
  metadata[:packages] << package
  File.binwrite(File.join(build, name), bytes)
  metadata[:files][name] = Digest::SHA256.hexdigest(bytes)
  filename = File.join(root, 'run/bundle/ruby/4.0.0/gems/messageformat-wrapper-1.1.0/dist', name)
  packet << [filename, bytes]
end
File.write(File.join(build, 'wrapper.js'), wrappers.first)
metadata[:files]['wrapper.js'] = Digest::SHA256.hexdigest(wrappers.first)
packet << ['', wrappers.first]
File.write(File.join(build, 'source-packet.json'), JSON.generate(packet))
metadata[:files]['source-packet.json'] = Digest::SHA256.file(File.join(build, 'source-packet.json')).hexdigest
File.write(File.join(build, 'source-lease.json'), JSON.pretty_generate(metadata) + "\n")
puts JSON.generate(metadata)
