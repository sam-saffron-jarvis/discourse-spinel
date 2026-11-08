# frozen_string_literal: true
# Actual source override read/output; no computed overrides supplied.
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
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "override source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
source = read.call('app/models/translation_override.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
scope = owner.body.body.grep(Prism::CallNode).find { |n| n.name == :scope && n.arguments.arguments.first.is_a?(Prism::SymbolNode) && n.arguments.arguments.first.unescaped == 'client_locales' }
raise 'client override scope missing' unless scope
proof[:spans] << {method: 'client_locales', start: scope.location.start_offset, end: scope.location.end_offset, sha256: Digest::SHA256.hexdigest(scope.slice)}
path = File.join(app, 'app/models/translation_override.rb')
model = File.read(path)
raise 'MF model class terminator changed' unless model.end_with?("\nend\n")
File.write(path, model.sub(/\nend\n\z/, "\ndef self.client_locales(locale)\n#{scope.arguments.arguments[1].body.slice}\nend\nend\n"))
source = read.call('lib/js_locale_helper.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :output_client_overrides }
raise 'client override output missing' unless node
proof[:spans] << {method: node.name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
original = File.join(build, 'original_client_locale_source.rb')
File.write(original, File.read(original) + "\nmodule OriginalClientLocaleSource\n#{node.slice}\nend\n")
native = node.slice.sub('def self.', 'def ').gsub('I18n.fallbacks[main_locale]', 'fallbacks(main_locale)')
native = native.gsub('overrides[locale]', 'overrides[locale.to_s]').gsub('.compact_blank', '.reject { |_locale, value| ActiveSupport.blank?(value) }')
native = native.gsub('all_overrides.blank?', 'ActiveSupport.blank?(all_overrides)')
native = native.sub('fallback_overrides.slice!(*fallback_overrides.keys - main_overrides.keys)', 'slice_override_fallback!(fallback_overrides, fallback_overrides.keys - main_overrides.keys)')
native = native.sub('all_overrides.reject { |_locale, value| ActiveSupport.blank?(value) }.to_json', 'client_override_json(all_overrides.reject { |_locale, value| ActiveSupport.blank?(value) })')
# Exact ActiveSupport slice! mutation + removed Hash return, specialized to
# plain source-created String/String pluck.to_h maps (nil default, no proc).
_, metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/core_ext/hash/slice.rb')
proof[:framework] = [metadata]
_, json_metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/json/encoding.rb')
proof[:framework] << json_metadata
output = File.join(build, 'request_client_locale_source.rb')
File.write(output, File.read(output) + <<~RUBY)
  class RequestClientLocaleSource
    def client_override_json(value)
      client_json(value).gsub("\u2028", '\\\\u2028').gsub("\u2029", '\\\\u2029')
    end
    def slice_override_fallback!(values, keys)
      omitted = values.reject { |key, _value| keys.include?(key) }
      kept = values.select { |key, _value| keys.include?(key) }
      values.replace(kept)
      omitted
    end
    #{native}
  end
RUBY
extra = File.join(build, 'request_extra_locale_source.rb')
text = File.read(extra)
anchor = "raise HtmlRenderingBoundary, 'actual main/MF locale scripts/preloads acquired; client override bundle acquisition pending'"
raise 'override acquisition boundary changed' unless text.scan(anchor).size == 1
File.write(extra, text.sub(anchor, 'RequestClientLocaleBootstrap.build_overrides(locale.to_s)'))
helpers = read.call('app/helpers/application_helper.rb')
owner = Prism.parse(helpers).value.statements.body.grep(Prism::ModuleNode).first
admin = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :admin? }
raise 'admin predicate missing' unless admin
proof[:spans] << {method: admin.name, start: admin.location.start_offset, end: admin.location.end_offset, sha256: Digest::SHA256.hexdigest(admin.slice)}
admin_body = admin.slice.sub('current_user.try(:admin?)', 'user = current_user; user && user.admin?')
File.write(File.join(build, 'client_override_layout_helpers.rb'), "module ClientOverrideLayoutHelpers\n#{admin_body}\nend\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = '<%= theme_translations_lookup %>'
last = layout.index(anchor)
raise 'override next layout boundary changed' unless last
prefix = layout[0, last + anchor.length] + "\n<% end %>"
prefix = prefix.gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
proof[:transformations] = ['Exact original client_locales scope chained to original enum-generated not_deprecated predicate', 'Original output_client_overrides with String JSON key normalization and explicit Rails HTML-escaped JSON', 'Original slice! removed-map return/mutation on plain pluck.to_h maps retained by named typed adapter', 'No empty digest cache hit injection; original ||= nil semantics retained', 'Next actual Theme translation helper explicitly refuses before missing bulk-cache acquisition']
File.write(File.join(build, 'client-overrides-source-proof.json'), JSON.pretty_generate(proof) + "\n")
