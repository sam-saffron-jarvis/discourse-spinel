# frozen_string_literal: true
require "prism"
require "digest"
require "json"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
app, build = ARGV
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, source: {}, spans: [], framework: [], full_layout_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "layout source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  proof[:source][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |source, name, singleton = nil|
  found = []
  walk = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name && (singleton.nil? || !node.receiver.nil? == singleton)
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(Prism.parse(source).value)
  raise "layout source method ambiguous #{name}" unless found.size == 1
  node = found.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
layout = read.call("app/views/layouts/application.html.erb")
head = read.call("app/views/layouts/_head.html.erb")
helper = read.call("app/helpers/application_helper.rb")
methods = %i[html_lang html_classes rtl? text_size_class title_content description_content theme_id current_homepage customization_disabled? render_sitelinks_search_tag discourse_pageview_tracking_meta_tags discourse_csrf_tags shared_session_key].map { |name| select.call(helper, name) }
version = read.call("lib/version.rb")[/STRING = ("[^"]+")/, 1]
rtl = read.call("lib/rtl.rb")[/LOCALES = (%w\[[^\]]+\])/, 1]
raise "layout declarations missing" unless version && rtl
mime, metadata = FidelitySourcePackage.member(root, "mini_mime-1.1.5", "lib/db/ext_mime.db")
proof[:framework] << metadata
mime_source, metadata = FidelitySourcePackage.member(root, "mini_mime-1.1.5", "lib/mini_mime.rb")
proof[:framework] << metadata
mime_table = mime.lines.to_h { |line| extension, type = line.split(/\s+/); [extension, type] }
File.write(File.join(app, "config/list_mime_types.json"), JSON.generate(mime_table))
File.write(File.join(build, "list_layout_source.rb"), "module ListLayoutSource\nVERSION_STRING = #{version}\nRTL_LOCALES = #{rtl}\nend\n")
original = "module OriginalListLayoutHelpers\n#{methods.join("\n")}\nend\nclass UrlHelper\n#{select.call(read.call("lib/url_helper.rb"), :absolute)}\nend\n"
original << "module Discourse\nmodule VERSION\nSTRING = ListLayoutSource::VERSION_STRING\nend\ndef self.git_version; PortableGitVersion.read(PortableGitVersion.application_root); end\ndef self.asset_host; SiteSetting.portable_rendering_asset_host; end\nend\n"
original << "class Rtl\nLOCALES = ListLayoutSource::RTL_LOCALES\nend\n"
compile = lambda { |source| ActionView::Template::Handlers::ERB::Erubi.new(source, escape: false, trim: true).src }
original << "module OriginalApplicationLayout\ndef render_application_layout\n#{compile.call(layout)}\nend\ndef render_head_partial\n#{compile.call(head)}\nend\nend\n"
File.write(File.join(build, "original_list_layout.rb"), original)
layout_end = layout.index('    <%= build_plugin_html')
head_end = head.bytesize
raise "layout prefix anchors changed" unless layout_end && head_end
layout_prefix = layout[0, layout_end]
head_prefix = head.dup
head_prefix = head_prefix.gsub('Discourse::VERSION::STRING', version).gsub('Discourse.git_version', 'PortableGitVersion.read(PortableGitVersion.application_root)')
head_prefix = head_prefix.gsub('SiteSetting.site_favicon_url.present?', 'ActiveSupport.present?(SiteSetting.site_favicon_url)').gsub('site_apple_touch_icon_url.present?', 'ActiveSupport.present?(site_apple_touch_icon_url)')
head_prefix = head_prefix.sub('MiniMime.lookup_by_filename(SiteSetting.site_favicon_url)&.content_type || "image/png"', 'list_icon_mime(SiteSetting.site_favicon_url)')
head_prefix = head_prefix.sub('::UrlHelper.absolute(site_apple_touch_icon_url)', 'ListHeadImages.full_cdn_url(site_apple_touch_icon_url)').gsub('Discourse.base_path.present?', 'ActiveSupport.present?(Discourse.base_path)').gsub('SiteSetting.google_site_verification_token.present?', 'ActiveSupport.present?(SiteSetting.google_site_verification_token)')
layout_prefix = layout_prefix.gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
File.write(File.join(build, "native_list_layout.rb"), "module NativeApplicationLayout\ndef render_application_layout\n#{compile.call(layout_prefix)}\nend\ndef render_head_partial\n#{compile.call(head_prefix)}\nend\nend\n")
color = read.call("app/models/color_scheme.rb")
read.call("app/assets/stylesheets/common/foundation/colors.scss")
base_colors = select.call(color, :base_colors, true)
lookup = select.call(color, :lookup_hex_for_name)
hex = select.call(color, :hex_for_name)
base_path = File.join(root, "discourse/app/assets/stylesheets/common/foundation/colors.scss")
File.write(File.join(build, "list_color_source.rb"), "module NativeListColorSource\nBASE_COLORS_FILE = #{base_path.inspect}\n@mutex = Mutex.new\n#{base_colors}\nend\n")
color_original = "module OriginalListColors\nBASE_COLORS_FILE = #{base_path.inspect}\n@mutex = Mutex.new\n#{base_colors}\n#{lookup}\n#{hex}\nend\n"
color_helpers = %i[discourse_theme_color_meta_tags discourse_color_scheme_meta_tag user_scheme_id scheme_id user_dark_scheme_id dark_scheme_id theme_limits_color_schemes? dark_color_scheme? light_color_hex_for_name dark_color_hex_for_name light_elements_media_query dark_elements_media_query forced_light_mode? forced_dark_mode?].map { |name| select.call(helper, name) }
color_original << "module OriginalListColorHelpers\nColorScheme = OriginalListColors\nmodule Theme\ndef self.find_by_id(id); ::Theme.find_by(id: id); end\ndef self.find_default; ::Theme.find_by(id: SiteSetting.default_theme_id); end\ndef self.where(**opts); ::Theme.where(**opts); end\nend\n#{color_helpers.join("\n")}\nend\n"
raise "invalid color source closure" unless Prism.parse(color_original).success?
File.write(File.join(build, "original_list_color.rb"), color_original)
# Additional readonly model declarations are acquired directly from the pin;
# do not mutate an existing immutable reference/source-copy inventory.
model_methods = %i[base_colors resolved_colors is_dark?]
model_constants = %i[NAMES_TO_ID_MAP BUILT_IN_SCHEMES LIGHT_PALETTE_NAME BASE_COLORS_FILE]
owner = Prism.parse(color).value.statements.body.grep(Prism::ClassNode).first
nodes = owner.body.body.select do |node|
  (node.is_a?(Prism::DefNode) && model_methods.include?(node.name)) ||
    (node.is_a?(Prism::ConstantWriteNode) && model_constants.include?(node.name)) ||
    (node.is_a?(Prism::CallNode) && (%i[default_scope has_many alias_method].include?(node.name) || node.name == :belongs_to && node.arguments.arguments.first.unescaped == "base_scheme"))
end
nodes.each { |node| proof[:spans] << {model: "ColorScheme", start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)} }
model_text = nodes.map(&:slice).join("\n")
model_text = model_text.sub(/^BASE_COLORS_FILE = .*$/, "BASE_COLORS_FILE = #{base_path.inspect}")
model_text = model_text.sub('default_scope { where(remote_copy: false) }', '# remote_copy default is applied at each scoped lookup; base_scheme explicitly unscopes it.')
model_text = model_text.sub('alias_method :colors, :color_scheme_colors', 'def colors; color_scheme_colors.to_a; end')
model_text = model_text.sub(/File\s*\n\s*\.readlines\(BASE_COLORS_FILE\)/, 'File.read(BASE_COLORS_FILE).lines')
File.write(File.join(app, "app/models/color_scheme.rb"), "class ColorScheme < ActiveRecord::Base\n#{model_text}\n@mutex = Mutex.new\nend\n")
read.call("app/models/color_scheme_color.rb")
File.write(File.join(app, "app/models/color_scheme_color.rb"), "class ColorSchemeColor < ActiveRecord::Base\nend\n")
File.write(File.join(app, "app/models/color_math.rb"), read.call("lib/color_math.rb"))
guardian_method = select.call(read.call("lib/guardian.rb"), :can_search?)
guardian_path = File.join(app, "app/models/guardian.rb")
File.write(guardian_path, File.read(guardian_path).sub(/end\s*\z/) { "#{guardian_method}\nend\n" })
canonical = read.call("lib/canonical_url.rb")
canonical_methods = %i[canonical_link_tag default_canonical append_content_localization_param].map { |name| select.call(canonical, name) }
File.write(File.join(build, "original_list_canonical.rb"), "module OriginalListCanonical\nALLOWED_CANONICAL_PARAMS = %w[page]\n#{canonical_methods.join("\n")}\nend\n")
proof[:prefix_bytes] = {layout: layout_prefix.bytesize, head: head_prefix.bytesize}
proof[:native_sha256] = Digest::SHA256.file(File.join(build, "native_list_layout.rb")).hexdigest
proof[:original_sha256] = Digest::SHA256.hexdigest(original)
File.write(File.join(build, "list-layout-source-proof.json"), JSON.pretty_generate(proof) + "\n")
