# frozen_string_literal: true
# New settings_hash CONSUMER span, not settings declaration/initializer replay.
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], full_settings_boot: false, page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG settings source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "SVG settings span ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
extension = read.call('lib/site_setting_extension.rb')
raw_hash = select.call(extension, :settings_hash)
setup = select.call(extension, :setup_methods)
deprecated = read.call('lib/site_settings/deprecated_settings.rb')
owner = Prism.parse(deprecated).value.statements.body.grep(Prism::ModuleNode).find { |n| n.constant_path.slice == 'SiteSettings::DeprecatedSettings' }
constant = owner.body.body.grep(Prism::ConstantWriteNode).find { |n| n.name == :SETTINGS }
deprecated_names = constant.value.elements.map { |n| n.elements.first.unescaped }
read.call('lib/site_settings/defaults_provider.rb')
types = read.call('lib/site_settings/type_supervisor.rb')
type_body = types.match(/Enum\.new\((.*?)\n\s*\)/m) or raise 'SVG settings type ABI missing'
type_names = type_body[1].scan(/(\w+):\s*(\d+)/).to_h.to_h { |name, id| [id.to_i, name.to_sym] }
read.call('config/site_settings.yml')
read.call('lib/discourse_plugin_registry.rb')
raw_hash = raw_hash.gsub('public_send(s, warn: false).to_s', 'SvgSettingsRead.record(s.to_s, public_send(s, warn: false).to_s)').gsub('public_send(s).to_s', 'SvgSettingsRead.record(s.to_s, public_send(s).to_s)')
File.write(File.join(build, 'original_svg_settings_source.rb'), <<~RUBY)
  module OriginalSvgSettingsMethods
    #{raw_hash}
    #{setup}
  end
RUBY
File.write(File.join(build, 'svg_settings_declarations.rb'), "module SvgSettingsDeclarations\nDEPRECATED = #{deprecated_names.inspect}\nTYPES = #{type_names.inspect}\nend\n")
upload = select.call(read.call('app/models/upload.rb'), :to_s)
file = File.join(app, 'app/models/upload.rb')
File.write(file, File.read(file).sub(/end\s*\z/) { "#{upload}\nend\n" })
proof[:transformations] = ['Source settings_hash keys projected from ordered core declarations excluding separately-defined default_locale; pure original DefaultsProvider independently checks key sequence', 'Only key order is projected, never DefaultsProvider values or full initialization; upcoming default overrides must target existing declared keys and no plugin/default modifiers may add keys', 'Candidate reads existing strict scalar API and exact upload getter cache/query/object.to_s; unsupported special getter refuses BEFORE replacing value', 'Third reference executes raw original settings_hash and setup_methods dynamically on fresh live current/provider metadata; no full Rails boot', 'Observed prefix names/value digests only; secret values not recorded, no partial Hash return']
File.write(File.join(build, 'svg-settings-source-proof.json'), JSON.pretty_generate(proof) + "\n")
