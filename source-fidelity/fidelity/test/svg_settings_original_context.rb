# frozen_string_literal: true
require_relative 'original_svg_settings_source'
module OriginalSvgSettingsMethods
  UpcomingChanges = OriginalHtmlStageSource::UpcomingChanges
end
module OriginalSvgSettingsReference
  class TypeView
    def get_type(name); SvgSettingsDeclarations::TYPES.fetch(SvgSettingsRead.definition(name.to_s).data_type); end
    def get_list_type(name); SvgSettingsRead.definition(name.to_s).options['list_type']; end
    def get_enum_class(name)
      definition = SvgSettingsRead.definition(name.to_s)
      return nil unless definition.options.key?('enum')
      # The only admitted enums have separately pinned class-body proofs that
      # wrap is absent. Do not invent a wrapper for other enum declarations.
      raise 'unsupported SVG original enum wrapper' unless definition.options['portable_unwrapped_enum'] == true
      nil
    end
  end
  class View
    include OriginalSvgSettingsMethods
    UpcomingChanges = OriginalHtmlStageSource::UpcomingChanges
    attr_reader :defaults
    def initialize
      @store = SiteSetting.portable_store
      @site = SiteSetting.portable_site
      @live = OriginalHtmlStageSource::LiveProviderView.new(@store, @site)
      @defaults = OriginalHtmlStageSource::DefaultsProvider.new(self)
      SvgSettingsRead.definitions.each do |definition|
        next if definition.name == 'default_locale'
        @defaults.load_setting(definition.name, definition.default_value, nil)
      end
      @type_view = TypeView.new
      @uploads = {}
      @installed = {}
    end
    def current; @store.svg_source_current(@site).transform_keys(&:to_sym); end
    def refresh!; @store.refresh!(@site); end
    def uploads; @uploads; end
    def theme_site_settings; {}; end
    def themeable
      SvgSettingsRead.definitions.to_h { |definition| [definition.name.to_sym, definition.themeable?] }
    end
    def plugins; @live.plugins; end
    def upcoming_change_default_overrides; @live.upcoming_change_default_overrides; end
    def type_supervisor; @type_view; end
    def mandatory_values
      SvgSettingsRead.definitions.each_with_object({}) do |definition, values|
        values[definition.name.to_sym] = definition.options['mandatory_values'] if definition.options.key?('mandatory_values')
      end
    end
    def deprecated_settings; SvgSettingsDeclarations::DEPRECATED.to_set; end
    def install_svg_getter_alias(name); nil; end
    def acquired_getter_value(name); raise "unacquired SVG named getter #{name}"; end
    def method_missing(name, *args, **kwargs)
      key = name.to_s
      branch = SvgSettingsRead.kind(key)
      SvgSettingsRead.pending(key) if branch == 'unsupported'
      return acquired_getter_value(key) if branch.start_with?('acquired_')
      raise 'recursive SVG original getter installation' if @installed[key]
      @installed[key] = true
      setup_methods(name)
      install_svg_getter_alias(name)
      public_send(name, *args, **kwargs)
    end
  end
  def self.settings_hash
    SvgSettingsRead.bind
    @view ||= View.new
    # DefaultsProvider.all may change DEFAULT VALUES through upcoming changes;
    # every such target is already declared, so keys/order remain unchanged.
    @view.upcoming_change_default_overrides.each_key do |key|
      raise 'SVG upcoming override introduced undeclared key' unless SvgSettingsRead.names.include?(key.to_s)
    end
    keys = @view.defaults.all.keys.map(&:to_s)
    raise 'SVG declaration key projection differs from source DefaultsProvider' unless keys == SvgSettingsRead.names
    @view.settings_hash
  end
end
module SvgSettingsRead
  def self.settings_hash; OriginalSvgSettingsReference.settings_hash; end
end
class OriginalListBodyContext
  include SvgSettingsViewProtocol
  def observation; svg_settings_stage_observation; end
end
