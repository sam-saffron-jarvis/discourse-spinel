# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, generic_wrapped_getter_supported: false, page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG wrapped source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
base = read.call('lib/enum_site_setting.rb')
source = read.call('app/models/duplicate_topic_titles_site_setting.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
raise 'wrapped class owner changed' unless owner.constant_path.slice == 'DuplicateTopicTitlesSiteSetting' && owner.superclass.slice == 'EnumSiteSetting'
activations = owner.body.body.grep(Prism::CallNode)
raise 'wrapped class gained other activation' unless activations.size == 1 && activations.first.slice == 'wrap_values!'
raise 'wrapped class methods changed' unless owner.body.body.all? { |n| n.is_a?(Prism::ConstantWriteNode) || (n.is_a?(Prism::DefNode) && n.receiver.is_a?(Prism::SelfNode) && %i[valid_value? values translate_names?].include?(n.name)) || n == activations.first }
base_owner = Prism.parse(base).value.statements.body.grep(Prism::ClassNode).first
wrap = base_owner.body.body.grep(Prism::DefNode).find { |n| n.name == :wrap_values! }
raise 'wrapper constructor/to_s purity changed' unless wrap.slice.include?('value_class = Class.new(String)') && wrap.slice.include?('define_singleton_method(:wrap) { |value| self::Value.new(value) }') && base_owner.body.body.all? { |n| n.is_a?(Prism::DefNode) && %i[translate_names? wrap_values!].include?(n.name) }
read.call('lib/site_setting_extension.rb')
File.write(File.join(build, 'original_svg_wrapped_source.rb'), "module OriginalSvgWrappedSource\n#{base_owner.slice}\n#{owner.slice}\nend\n")
proof[:transformations] = ['Candidate shared APPLICATION CONSUMER composition only: source pure String-subclass wrap(value.to_s).to_s -> fresh mutable plain String copy', 'No generic native wrapped getter, predicate methods, class identity or wrapper allocation claimed', 'Third reference executes actual raw wrap_values! class activation and actual source getter wrapper before String#to_s', 'Plain consumer String bytes/class/freeze/fresh identity proved; raw provider aliasing/frozen/wrong-value mutants reject', 'Only duplicate_topic_titles declaration accepted; String/asset Array/cache contracts unchanged']
File.write(File.join(build, 'svg-wrapped-source-proof.json'), JSON.pretty_generate(proof) + "\n")
