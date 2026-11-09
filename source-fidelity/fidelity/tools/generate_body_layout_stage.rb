# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], framework: [], page_accepted: false, full_layout_completed: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "body layout source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(source)
  source
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "body layout method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
helper = read.call('app/helpers/application_helper.rb')
config = select.call(helper, :discourse_config_environment).sub('def discourse_config_environment', 'def source_config_environment')
body = select.call(helper, :body_classes).sub('def body_classes', 'def source_body_classes')
auth = select.call(helper, :authentication_data).sub('def authentication_data', 'def source_authentication_data')
custom = select.call(helper, :custom_splash_screen_enabled?).sub('def custom_splash_screen_enabled?', 'def source_custom_splash_screen_enabled?')
extra = select.call(helper, :extra_body_classes)
File.write(File.join(build, 'body_layout_read_source.rb'), "module BodyLayoutRead\n#{extra}\nend\n")
controller = read.call('app/controllers/application_controller.rb')
splash = select.call(controller, :include_splash_screen?).sub('def include_splash_screen?', 'def source_include_splash_screen?')
common = "#{body.gsub('ApplicationHelper.extra_body_classes', 'BodyLayoutRead.extra_body_classes')}\n#{auth}\n#{custom.gsub('SiteSetting.splash_screen_image', 'BodyLayoutRead.source_upload')}\n#{splash}\n"
native_config = config.gsub('Rails.env', "ENV.fetch('RAILS_ENV')").gsub('Discourse::VERSION::STRING', 'ListLayoutSource::VERSION_STRING').gsub('Discourse.git_version', 'PortableGitVersion.read(PortableGitVersion.application_root)').sub('config.to_json', 'JsonBuilder.escape_html_entities(JSON.generate(config))')
native_common = common.gsub('@category.url.present?', 'ActiveSupport.present?(@category.url)').gsub('current_user.present?', 'ActiveSupport.present?(current_user)')
File.write(File.join(build, 'body_layout_source.rb'), "module BodyLayoutSource\n#{native_config}\n#{native_common}\nend\n")
File.write(File.join(build, 'original_body_layout_source.rb'), "module OriginalBodyLayoutSource\nRails = OriginalClientSetupHelpers::Rails\n#{config}\n#{common}\n#{select.call(helper, :light_color_hex_for_name)}\n#{select.call(helper, :dark_color_hex_for_name)}\nColorScheme = OriginalListColors\nend\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = '        <%= render partial: "common/discourse_stylesheet" %>'
raise 'body stylesheet cursor changed' unless layout.scan(anchor).size == 1
prefix = layout[0, layout.index(anchor) + anchor.length]
compile = lambda { |source| ActionView::Template::Handlers::ERB::Erubi.new(source, escape: false, trim: true).src }
File.write(File.join(build, 'body_layout_template.rb'), "module BodyLayoutTemplate\ndef render_application_layout\n#{compile.call(prefix.gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")'))}\nend\nend\n")
File.write(File.join(build, 'original_body_layout_template.rb'), "module OriginalBodyLayoutTemplate\nGlobalSetting = OriginalApplicationLayout::GlobalSetting\ndef render_application_layout\n#{compile.call(prefix)}\nend\nend\n")
# Preserve the exact source Boolean predicate contract for this lowering.
select.call(helper, :splash_screen_image_animated?)
partial = read.call('app/views/common/_discourse_splash.html.erb')
native_partial = partial.gsub('if splash_screen_image_animated?', 'if splash_screen_image_animated? == true').gsub('unless splash_screen_image_animated?', 'unless splash_screen_image_animated? == true')
File.write(File.join(build, 'body_splash_template.rb'), "module BodySplashTemplate\ndef render_splash_partial\n#{compile.call(native_partial)}\nend\nend\n")
File.write(File.join(build, 'original_body_splash_template.rb'), "module OriginalBodySplashTemplate\ndef render_splash_partial\n#{compile.call(partial)}\nend\nend\n")
_, metadata = FidelitySourcePackage.member(root, 'actionview-8.1.4', 'lib/action_view/template/handlers/erb/erubi.rb')
proof[:framework] << metadata
_, metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/core_ext/erb/util.rb')
proof[:framework] << metadata
_, metadata = FidelitySourcePackage.member(root, 'erb-6.0.7', 'lib/erb/util.rb')
proof[:framework] << metadata
proof[:template_prefix] = {bytes: prefix.bytesize, sha256: Digest::SHA256.hexdigest(prefix), boundary: 'first actual stylesheet partial call before any stylesheet acquisition/effect'}
proof[:transformations] = ['Actual config Hash/JSON/component-URI u consumer; only environment immediate JSON String projection, raw original helper separate', 'Actual anonymous body classes, missing-cookie authentication memo, real nullable upload custom splash decision, controller environment predicate', 'Complete actual splash partial, existing live palette ORM and real source-owned color-cache lifecycle; only secondary/tertiary names added to prior guarded cache', 'Raw original independent ActionView/JSON/ERB util and original ColorScheme lookup; nonempty image/auth/category/user profiles explicitly refuse', 'Boolean source image predicate compared ==true only in candidate; unsupported helper still raises, raw original partial unchanged', 'Exact stylesheet boundary is effect refusal, not a fabricated stylesheet or completed layout/page']
File.write(File.join(build, 'body-layout-source-proof.json'), JSON.pretty_generate(proof) + "\n")
