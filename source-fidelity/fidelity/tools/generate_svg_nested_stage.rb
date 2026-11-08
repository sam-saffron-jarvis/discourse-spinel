# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'yaml'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:app/models/site_setting.rb")
raise 'SiteSetting lexical source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/app/models/site_setting.rb'))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).find { |n| n.constant_path.slice == 'SiteSetting' }
raise 'SiteSetting lexical owner missing' unless owner
records = []
walk = lambda do |node, scope, singleton|
  if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
    path = node.equal?(owner) ? 'SiteSetting' : scope + '::' + node.constant_path.slice
    node.compact_child_nodes.each { |child| walk.call(child, path, false) }
  elsif node.is_a?(Prism::SingletonClassNode)
    raise 'unsupported SiteSetting singleton receiver' unless node.expression.is_a?(Prism::SelfNode)
    node.compact_child_nodes.each { |child| walk.call(child, scope, true) }
  elsif node.is_a?(Prism::DefNode)
    records << [node.name.to_s, scope] if node.receiver.is_a?(Prism::SelfNode) || (node.receiver.nil? && singleton)
  else
    node.compact_child_nodes.each { |child| walk.call(child, scope, singleton) }
  end
end
walk.call(owner, '', false)
top = records.select { |_, scope| scope == 'SiteSetting' }.map(&:first)
nested = records.reject { |_, scope| scope == 'SiteSetting' || scope == '' }.to_h
false_positives = nested.reject { |name, _| top.include?(name) }
raise 'S3 top-level/nested scope changed' unless false_positives['enable_s3_uploads'] == 'SiteSetting::Upload'
File.write(File.join(build, 'svg_nested_declarations.rb'), "module SvgNestedDeclarations\nSCOPES = #{false_positives.inspect}\nend\n")
File.write(File.join(build, 'svg-nested-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), direct_top_level_methods: top, nested_methods_not_top_level: false_positives, transformations: ['AST lexical-owner classification, never regex override inference', 'Exact generated top-level primitive getter consumer for source-proven nested-only names; existing conservative flags unchanged', 'Nested Upload/ImageQuality helper bodies NOT invoked; named enum/source/plugin/override profiles still refuse', 'Existing local upload/S3-disabled configuration guard retained; no S3 client/action/network request'], full_settings_boot: false, page_accepted: false}) + "\n")
