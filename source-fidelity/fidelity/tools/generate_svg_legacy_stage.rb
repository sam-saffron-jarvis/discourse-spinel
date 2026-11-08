# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:lib/site_settings/deprecated_settings.rb")
raise 'SVG deprecated source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/lib/site_settings/deprecated_settings.rb'))
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).find { |n| n.constant_path.slice == 'SiteSettings::DeprecatedSettings' }
constant = owner.body.body.grep(Prism::ConstantWriteNode).find { |n| n.name == :SETTINGS }
rows = constant.value.elements.map do |row|
  old, replacement, override, version = row.elements
  raise 'unsupported deprecated override declaration' unless override.is_a?(Prism::FalseNode)
  [old.unescaped, replacement.unescaped, false, version.unescaped]
end
node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :setup_deprecated_method }
body = node.slice.gsub('SiteSetting.singleton_class.alias_method', 'singleton_class.alias_method')
anchor = 'public_send(override ? new_setting : "_#{old_setting}", scoped_to)'
raise 'source deprecated getter forwarding changed' unless body.scan(anchor).size == 1
body = body.sub(anchor, 'target = override ? new_setting : "_#{old_setting}"; SvgLegacyRead.note(old_setting.to_s, target.to_s, warn); public_send(target, scoped_to)')
File.write(File.join(build, 'svg_legacy_source.rb'), "module SvgLegacyDeclarations\nALIASES = #{rows.to_h { |old, replacement, _, _| [old, replacement] }.inspect}\nVERSIONS = #{rows.to_h { |old, _, _, version| [old, version] }.inspect}\nend\n")
File.write(File.join(build, 'original_svg_legacy_source.rb'), "module OriginalSvgLegacyMethods\n#{body}\nend\n")
File.write(File.join(build, 'svg-legacy-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), span: {start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}, declarations: rows, transformations: ['Only source override:false aliases in settings_hash warn:false consumer; other warning/override profiles refuse', 'Candidate reads original old-setting getter, never replacement setting; raw reference installs source aliases/getter/question/setter methods without invoking writes', 'Original alias installation owner bound to scoped reference instance rather than live global SiteSetting', 'Source selected forwarding target and warn flag observed without changing return value or suppressing applicable warning'], full_settings_boot: false, page_accepted: false}) + "\n")
