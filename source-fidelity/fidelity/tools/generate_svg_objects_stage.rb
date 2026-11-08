# frozen_string_literal: true
require 'prism'
require 'yaml'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, full_settings_boot: false, page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG objects source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(source)
  source
end
settings = YAML.safe_load(read.call('config/site_settings.yml'), aliases: true).values.reduce({}, :merge)
objects = settings.select { |_, definition| definition.is_a?(Hash) && definition['type'] == 'objects' }
raise 'SVG objects source family changed' unless objects.keys == ['dsa_community_rules'] && objects.values.first['default'] == []
types = read.call('lib/site_settings/type_supervisor.rb')
nodes = []
visit = lambda do |node|
  nodes << node if node.is_a?(Prism::DefNode) && node.name == :to_rb_value
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(types).value)
raise 'SVG objects coercion source changed' unless nodes.size == 1 && nodes.first.slice.include?('return value if self.class.types[type]') && !nodes.first.slice.include?('types[:objects]')
read.call('lib/site_setting_extension.rb')
proof[:setting] = 'dsa_community_rules'
proof[:source_default_class] = objects.values.first['default'].class.name
proof[:coercion_sha256] = Digest::SHA256.hexdigest(nodes.first.slice)
proof[:transformations] = ['Source objects type28 returns input unchanged; current is actual declaration Array or actual stored wire String, never JSON-parsed by GET', 'No objects validator/schema normalization/setter invoked; unsupported nonempty Array profile refuses', 'Native/shared preserve current reference and freezing then actual to_s; isolated original executes raw setup_methods and observes returned object before to_s', 'No synthesized default value/cache seed/row or broad Array relaxation']
File.write(File.join(build, 'svg-objects-source-proof.json'), JSON.pretty_generate(proof) + "\n")
