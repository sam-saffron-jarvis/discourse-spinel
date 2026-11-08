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
  raise "head configuration source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |text, names|
  owner = Prism.parse(text).value.statements.body.grep(Prism::ModuleNode).first
  names.map do |name|
    node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == name }
    raise "head configuration method missing #{name}" unless node
    proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
    node.slice.sub("def #{name}", "def source_#{name}")
  end
end
common = select.call(read.call('app/helpers/common_helper.rb'), %i[render_google_tag_manager_head_code render_google_universal_analytics_code render_adobe_analytics_tags_code suppress_analytics_in_embed?])
application = select.call(read.call('app/helpers/application_helper.rb'), %i[manifest_url include_ios_native_app_banner? ios_app_argument])
original = common + application
native = original.map do |text|
  text.gsub('SiteSetting.ga_universal_tracking_code.present?', 'ActiveSupport.present?(SiteSetting.ga_universal_tracking_code)').gsub('SiteSetting.gtm_container_id.present?', 'ActiveSupport.present?(SiteSetting.gtm_container_id)').gsub('SiteSetting.adobe_analytics_tags_url.present?', 'ActiveSupport.present?(SiteSetting.adobe_analytics_tags_url)').gsub('params[:embed_mode].present?', 'ActiveSupport.present?(params[:embed_mode])').gsub('content_tag(:script,', 'unsupported_analytics_content_tag(:script,')
end
File.write(File.join(build, 'head_configuration_helpers.rb'), "module HeadConfigurationHelpers\n#{native.join("\n")}\ndef unsupported_analytics_content_tag(*args, **options); raise ArgumentError, 'unsupported active analytics script profile'; end\nend\n")
File.write(File.join(build, 'original_head_configuration_helpers.rb'), "module OriginalHeadConfigurationHelpers\n#{original.join("\n")}\nend\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = '<%= yield :head %>'
finish = layout.index(anchor)
raise 'head configuration yield boundary missing' unless finish
prefix = layout[0, finish + anchor.length].gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
proof[:transformations] = ['Actual analytics/suppression, manifest and iOS helper predicates consume real settings/request/user; no blank settings supplied', 'Unsupported active analytics rendering explicitly refuses; no external script/process executed', 'Source yield(:head) actually enters runner block; block refuses before unacquired original layout_for/view-flow capability']
File.write(File.join(build, 'head-configuration-source-proof.json'), JSON.pretty_generate(proof) + "\n")
