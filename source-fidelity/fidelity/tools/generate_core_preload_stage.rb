# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "core preload source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
source = read.call('app/helpers/application_helper.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
methods = %i[preload_script module_preloads_for].map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == name }
  raise "core preload helper missing #{name}" unless node
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice.sub("def #{name}", "def source_#{name}")
end
native = methods.map { |text| text.gsub('EmberAssets.script_chunks', 'request_assets.script_chunks').sub('modulepreload_tags.join("\n").html_safe', 'ActionView::HtmlFragment.new(modulepreload_tags.join("\n"))') }
File.write(File.join(build, 'core_preload_helpers.rb'), "module CorePreloadHelpers\n#{native.join("\n")}\nend\n")
File.write(File.join(build, 'original_core_preload_helpers.rb'), "module OriginalCorePreloadHelpers\nEmberAssets = OriginalAssetLifecycle::EmberAssets\n#{methods.join("\n")}\nend\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = '<%= theme_lookup("head_tag") %>'
finish = layout.index(anchor)
raise 'core preload next boundary changed' unless finish
prefix = layout[0, finish + anchor.length] + "\n<% end %>"
prefix = prefix.gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
proof[:transformations] = ['Exact source preload_script/module_preloads_for: concrete owned EmberAssets receiver, preserved chunks/fallback/compact/uniq/order and actual Propshaft resolution', 'Original helper full bodies run against original EmberAssets class in third process', 'Typed HtmlFragment represents original HtmlSafe join; source preload_script safe return identity retained', 'Next actual head_tag Theme field helper explicitly refuses, no skipped supported call']
File.write(File.join(build, 'core-preload-source-proof.json'), JSON.pretty_generate(proof) + "\n")
