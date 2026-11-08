# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG theme source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(source)
  source
end
select = lambda do |source, name|
  nodes = []
  walk = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(Prism.parse(source).value)
  raise "SVG theme method ambiguous #{name}" unless nodes.size == 1
  proof[:spans] << {name: name, sha256: Digest::SHA256.hexdigest(nodes.first.slice)}
  nodes.first.slice
end
theme = read.call('app/models/theme.rb')
methods = %i[cached_settings settings build_settings_hash build_theme_uploads_hash build_local_theme_uploads_hash build_theme_setting_type_info_hash group_setting_alias_enabled?].to_h { |name| [name, select.call(theme, name)] }
field = read.call('app/models/theme_field.rb')
raise 'SVG theme settings association changed' unless theme.include?('where(target_id: Theme.targets[:settings], name: "yaml")') && theme.include?('where(type_id: ThemeField.types[:theme_upload_var]).preload(:upload)')
raise 'SVG theme upload type changed' unless select.call(field, :types).include?('theme_upload_var: 2,')
model = File.join(app, 'app/models/theme_field.rb')
File.write(model, File.read(model).sub('class ThemeField < ActiveRecord::Base', 'class ThemeField < ActiveRecord::Base' + "\n  belongs_to :upload\n  has_one :javascript_cache, -> { where(name: nil) }"))
# Full original methods are retained for independent source execution. Native
# misses/empty loops have explicit next-collaborator refusal, never fake values.
native = methods.values.join("\n").gsub('Theme.get_set_cache ', 'SvgThemeIcons.cache_settings ').gsub('ThemeSettingsParser', 'SvgThemeSettingsParserRead').gsub('ThemeSettingsManager', 'SvgThemeSettingsManagerRead').gsub('SiteSetting.granular_anonymous_and_logged_in_groups_permissions', "SvgExperimentalRead.enabled('granular_anonymous_and_logged_in_groups_permissions')")
# The renamed native parser is the first unacquired collaborator. Keep the
# original body only in the independent original, not generic callback stand-ins.
source_settings = methods[:settings].gsub('ThemeSettingsParser', 'SvgThemeSettingsParserRead').gsub('ThemeSettingsManager', 'SvgThemeSettingsManagerRead')
native_settings = "def settings\n  field = settings_field\n  settings = {}\n  if field && field.error.nil?\n    raise ArgumentError, 'nonempty SVG Theme settings parser profile unacquired'\n  end\n  settings\nend"
raise 'SVG theme native settings body changed' unless native.include?(source_settings)
native = native.sub(source_settings, native_settings)
native = native.gsub('settings_hash[name] = setting.value', "raise ArgumentError, 'nonempty SVG Theme setting value profile unacquired'")
info = methods[:build_theme_setting_type_info_hash]
native = native.sub(info, "def build_theme_setting_type_info_hash; raise ArgumentError, 'nonempty SVG Theme setting metadata profile unacquired'; end")
native = native.gsub('theme_uploads.present?', '!ActiveSupport.blank?(theme_uploads)').gsub('theme_uploads_local.present?', '!ActiveSupport.blank?(theme_uploads_local)')
native = native.gsub('hash[field.name] = Discourse.store.cdn_url(field.upload.url) if field.upload&.url', "raise ArgumentError, 'nonempty SVG theme upload profile unacquired'")
native = native.gsub('hash[field.name] = field.javascript_cache.local_url if field.javascript_cache', "raise ArgumentError, 'nonempty SVG local theme upload profile unacquired'")
svg = read.call('lib/svg_sprite.rb')
icons = select.call(svg, :theme_icons)
icons = icons.sub('settings = theme.cached_settings', 'settings = SvgThemeSettingsRead.new(theme).cached_settings').sub('ThemeModifierHelper.new', 'SvgThemeModifierRead.new')
lookup = select.call(theme, :lookup_modifier).sub('def self.lookup_modifier', 'def self.lookup_modifier').gsub('Theme.compiler_version', 'ListThemeCompilerSource.compiler_version').sub('get_set_cache(', 'cache_modifier(')
read.call('lib/theme_modifier_helper.rb')
read.call('app/models/theme_modifier_set.rb')
File.write(File.join(build, 'svg_theme_icons_source.rb'), <<~RUBY)
  module SvgThemeSettingsMethods
    #{native}
  end
  module SvgThemeIcons
    #{lookup}
  end
  module RequestSvgSource
    #{icons.gsub('theme_id.blank?', 'ActiveSupport.blank?(theme_id)')}
  end
RUBY
original = methods.values.join("\n")
File.write(File.join(build, 'original_svg_theme_icons_source.rb'), <<~RUBY)
  module OriginalSvgThemeSettingsMethods
    module Theme
      def self.get_set_cache(key); SvgThemeIcons.cache_settings(key) { yield }; end
    end
    module SiteSetting
      def self.granular_anonymous_and_logged_in_groups_permissions
        view = OriginalHtmlStageSource::LiveProviderView.new(::SiteSetting.portable_store, ::SiteSetting.portable_site)
        OriginalHtmlStageSource::UpcomingChanges.live_provider = view
        OriginalHtmlStageSource::UpcomingChanges.enabled?(:granular_anonymous_and_logged_in_groups_permissions)
      end
    end
    ThemeSettingsParser = SvgThemeSettingsParserRead
    ThemeSettingsManager = SvgThemeSettingsManagerRead
    #{original}
  end
  class OriginalSvgThemeSettingsRead < SvgThemeSettingsRead
    include OriginalSvgThemeSettingsMethods
  end
  module OriginalRequestSvgSource
    #{icons.sub('SvgThemeSettingsRead.new', 'OriginalSvgThemeSettingsRead.new')}
    def self.custom_icons(theme_id)
      raise HtmlRenderingBoundary, 'actual SVG theme settings/modifier icons acquired; custom SVG/XML acquisition pending'
    end
  end
RUBY
proof[:transformations] = ['Actual settings_field has_one nil memo and upload_fields scope/preloads expanded from pinned associations into real readonly emitted AR relations', 'Source cached_settings/settings/build_settings_hash and real empty loops; nonempty settings parser/upload collaborators explicitly refuse', 'Source group-alias upcoming getter and source cache key; independent original raw upcoming enabled? and source settings methods', 'Source svg_icons helper resolves actual ThemeModifierSet rows/catalog; original distributed cache wrapper restored in scoped typed Array domain', 'Only empty settings Hash cache domain admitted; existing String/extra_js Array guards unchanged; no seeded values or skipped applicable callbacks']
File.write(File.join(build, 'svg-theme-icons-source-proof.json'), JSON.pretty_generate(proof) + "\n")
