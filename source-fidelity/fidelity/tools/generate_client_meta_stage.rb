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
proof = {pin: pin, sources: {}, framework: [], spans: [], page_accepted: false, generic_environment_object_api_supported: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "client meta source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
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
  raise "client meta method ambiguous #{name}" unless nodes.size == 1
  proof[:spans] << {name: name, sha256: Digest::SHA256.hexdigest(nodes.first.slice)}
  nodes.first
end
application = read.call('app/helpers/application_helper.rb')
helper = select.call(application, :client_side_setup_data)
first_keys = helper.body.body.first.value.elements.map { |node| node.key.unescaped.to_sym }
keys = first_keys + %i[svg_icon_list debug_preloaded_app_data mb_last_file_change_id capybara_playwright_debug_client_settled raise_on_deprecation safe_mode s3_cdn s3_base_url]
File.write(File.join(build, 'client_meta_declarations.rb'), "module ClientMetaDeclarations\nKEYS = #{keys.inspect}\nFIRST_KEYS = #{first_keys.inspect}\nend\n")
# Reuse the existing independently observed first-eight-input wrappers; continue
# the actual full helper instead of reconstructing its values.
original = select.call(File.read(File.join(build, 'original_client_setup_source.rb')), :source_client_side_setup_data).slice
native = original.gsub('Rails.configuration.action_controller.asset_host', 'settings.asset_host').gsub('Rails.env', "ClientMetaRead.environment").gsub('LetterAvatar.version', 'PortableLetterAvatarVersion.version').gsub('Discourse.assets_digest', 'ClientSetupReadBootstrap.asset_version').gsub('HighlightJs.path', 'ClientHighlightBootstrap.path').gsub('SvgSprite.path(theme_id)', 'client_setup_svg_path(theme_id)').gsub('SvgSprite.all_icons(theme_id)', 'ClientMetaRead.all_icons(theme_id)').gsub('GlobalSetting.enable_js_error_reporting', 'ClientMetaRead.error_reporting').gsub('MessageBus.last_id(', 'ClientMetaRead.last_id(')
native = native.gsub('ENV["CAPYBARA_PLAYWRIGHT_DEBUG_CLIENT_SETTLED"].present?', 'ActiveSupport.present?(ENV["CAPYBARA_PLAYWRIGHT_DEBUG_CLIENT_SETTLED"])')
# The source environment object is consumed immediately as a String attribute.
# Native's existing prefix uses the exact actual name String; never advertise
# generic EnvironmentInquirer return/class/predicate support.
native = native.sub('ClientMetaRead.environment)),', "ENV.fetch('RAILS_ENV'))),")
if_nodes = []
visit = lambda do |node|
  if_nodes << node if node.is_a?(Prism::IfNode) && node.predicate.slice == 'SiteSetting.Upload.enable_s3_uploads'
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(native).value)
raise 'client meta S3 source branch changed' unless if_nodes.size == 1
native = native.sub(if_nodes.first.slice, "if ClientMetaUploadRead.enable_s3_uploads\n    raise ArgumentError, 'unsupported client setup S3 URL profile'\n  end")
File.write(File.join(build, 'client_meta_source.rb'), "module ClientMetaSource\n#{native}\nend\n")
# Actual source computed GlobalSetting S3 memo and nested Upload Boolean helper.
global = read.call('app/models/global_setting.rb')
use_s3 = select.call(global, :use_s3?).slice
setting = read.call('app/models/site_setting.rb')
uploads = select.call(setting, :enable_s3_uploads).slice.gsub('SiteSetting.enable_s3_uploads', "SvgNestedRead.current('enable_s3_uploads')").gsub('GlobalSetting.use_s3?', 'ClientMetaGlobalStorage.use_s3?')
getters = %w[s3_bucket s3_region s3_use_iam_profile s3_access_key_id s3_secret_access_key].map { |key| "def self.#{key}; ListHeadImages.configuration.value(#{key.dump}); end" }.join("\n")
File.write(File.join(build, 'client_meta_storage_source.rb'), "module ClientMetaGlobalStorage\n#{getters}\n#{use_s3}\nend\nmodule ClientMetaUploadRead\n#{uploads}\nend\n")
# Source has_one/cookie/anon nil branches only; nonempty user choice needs its
# own ColorScheme lookup/validation contract rather than a forged default ID.
user_sources = %i[user_scheme_id user_dark_scheme_id].map { |name| select.call(application, name).slice }
File.write(File.join(build, 'original_client_meta_palette.rb'), "module OriginalClientMetaPalette\n#{user_sources.join("\n")}\nend\n")
package = 'message_bus-4.5.2'
# Derive exact installed/locked version, never substitute a different backend.
lock = File.read(File.join(root, 'discourse/Gemfile.lock'))
version = lock[/^    message_bus \(([^)]+)\)/, 1] or raise 'message_bus lock missing'
package = 'message_bus-' + version
bus_source, metadata = FidelitySourcePackage.member(root, package, 'lib/message_bus.rb')
proof[:framework] << metadata
last = select.call(bus_source, :last_id).slice
File.write(File.join(build, 'client_meta_bus_source.rb'), "module CategoryCacheMessageBus::Implementation\n#{last}\nend\n")
tag, metadata = FidelitySourcePackage.member(root, 'actionview-8.1.4', 'lib/action_view/helpers/tag_helper.rb')
proof[:framework] << metadata
%i[define_void_element tag_options prefix_tag_option tag_option self_closing_tag_string].each { |name| select.call(tag, name) }
layout = read.call('app/views/layouts/application.html.erb')
anchor = %q[<%= tag.meta id: 'data-discourse-setup', data: client_side_setup_data %>]
raise 'client meta template cursor changed' unless layout.scan(anchor).size == 1
prefix = layout[0, layout.index(anchor) + anchor.length]
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'original_client_meta_layout.rb'), "module OriginalClientMetaLayout\nGlobalSetting = OriginalApplicationLayout::GlobalSetting\ndef render_application_layout\n#{code}\nend\nend\n")
proof[:original_template_prefix] = {bytes: prefix.bytesize, sha256: Digest::SHA256.hexdigest(prefix), boundary: 'immediately after actual setup meta append; remaining template not executed'}
proof[:transformations] = ['Continue actual client setup source Hash/development/file-change/safe-mode/Upload Boolean ordering and callbacks on admitted anonymous no-cookie development profile', 'Existing live scalar/config/read-only palette inputs; original full helper/palette methods execute separately', 'Source environment StringInquirer is projected ONLY at immediate meta attribute String consumer; generic environment/Hash object API not claimed', 'Source TagBuilder void meta id/data branch specialized using existing exact HTML and Rails8.1 JSON escaping, raw actual ActionView builder reference unchanged', 'Real MessageBus last_id site encoding and backend GET on owned fixture only; new /file-change READ scope, no publication authority']
File.write(File.join(build, 'client-meta-source-proof.json'), JSON.pretty_generate(proof) + "\n")
