# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:app/models/translation_override.rb")
raise 'MF override source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/app/models/translation_override.rb'))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
scope = owner.body.body.grep(Prism::CallNode).find { |n| n.name == :scope && n.arguments.arguments.first.is_a?(Prism::SymbolNode) && n.arguments.arguments.first.unescaped == 'mf_locales' }
enum = owner.body.body.grep(Prism::CallNode).find { |n| n.name == :enum && n.arguments.arguments.first.is_a?(Prism::SymbolNode) && n.arguments.arguments.first.unescaped == 'status' }
raise 'MF scope/status source missing' unless scope && enum
entry = enum.arguments.arguments[1].elements.find { |n| n.key.is_a?(Prism::SymbolNode) && n.key.unescaped == 'deprecated' }
raise 'MF deprecated declaration is not Integer' unless entry.value.is_a?(Prism::IntegerNode)
expression = scope.arguments.arguments[1].body.slice
path = File.join(app, 'app/models/translation_override.rb')
File.write(path, "class TranslationOverride < ActiveRecord::Base\ndef self.not_deprecated; where.not(status: #{entry.value.slice}); end\ndef self.mf_locales(locale)\n#{expression}\nend\nend\n")
extra = File.join(build, 'request_extra_locale_source.rb')
text = File.read(extra)
anchor = "raise HtmlRenderingBoundary, 'actual main locale JS/digest/preload acquired; MessageFormat compiler acquisition pending'"
raise 'MF boundary changed' unless text.scan(anchor).size == 1
text = text.sub(anchor, "RequestClientLocaleBootstrap.build_mf(locale.to_s)\n      when OVERRIDES_BUNDLE\n        RequestClientLocaleBootstrap.events << 'locale_bundle_acquisition:overrides'\n        raise HtmlRenderingBoundary, 'actual main/MF locale scripts/preloads acquired; client override bundle acquisition pending'")
File.write(extra, text)
layout, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:app/views/layouts/application.html.erb")
raise 'MF layout source changed' unless status.success? && layout.b == File.binread(File.join(root, 'discourse/app/views/layouts/application.html.erb'))
anchor = '<%- if ExtraLocalesController.client_overrides_exist? %>'
last = layout.index(anchor)
raise 'MF layout next boundary changed' unless last
prefix = layout[0, last + anchor.length] + "\n<% end %>"
prefix = prefix.gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
_, indent_metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/core_ext/string/indent.rb')
File.write(File.join(build, 'messageformat-source-proof.json'), JSON.pretty_generate({pin: pin, framework: [indent_metadata], source_sha256: Digest::SHA256.hexdigest(source),
  scope_span: {start: scope.location.start_offset, end: scope.location.end_offset, sha256: Digest::SHA256.hexdigest(scope.slice)},
  enum_span: {start: enum.location.start_offset, end: enum.location.end_offset, sha256: Digest::SHA256.hexdigest(enum.slice)},
  transformations: ['Exact source mf_locales scope and enum-generated not_deprecated predicate, no replacement SQL', 'Previous MF refusal lifts only after owned original compiler acquisition; next overrides branch refuses'], page_accepted: false}) + "\n")
