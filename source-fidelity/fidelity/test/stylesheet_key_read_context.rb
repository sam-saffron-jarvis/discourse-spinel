# frozen_string_literal: true
require_relative "stylesheet_key_source"
class GlobalSetting
  def self.relative_url_root; StylesheetKeyRead.relative_url_root; end
end
module StylesheetKeyRead
  def self.configure(configuration)
    @configuration = configuration
    nil
  end
  def self.relative_url_root
    value = @configuration.value('relative_url_root')
    raise ArgumentError, 'stylesheet relative root must be nullable String' unless value.nil? || value.is_a?(String)
    value = '/wrong-root' if ENV.fetch('FIDELITY_STYLESHEET_KEY_FAULT', '') == 'wrong-root'
    value
  end
  def self.source_key(record, theme_id)
    StylesheetKeySource.color_scheme_cache_key(record, theme_id)
  end
  def self.source_slug(text); Slug.for(text); end
  def self.acquire
    record = PaletteBaseRead.source_base
    theme_id = SiteSetting.default_theme_id
    fault = ENV.fetch('FIDELITY_STYLESHEET_KEY_FAULT', '')
    source_slug("café") if fault == 'non-ascii'
    record.read_attribute(:version) if fault == 'wrong-attribute'
    root = relative_url_root
    raise 'stylesheet global relative root changed' unless root == @configuration.value('relative_url_root')
    hostname = Discourse.current_hostname
    raise 'stylesheet hostname is not String' unless hostname.is_a?(String)
    raise 'localized palette name changed stylesheet key' unless record.read_attribute(:name) == record.source_raw_palette_name
    keys = [source_key(record, nil), source_key(record, theme_id)]
    raise 'stylesheet theme key lost' if !theme_id.nil? && keys[0] == keys[1]
    old = I18n.locale
    begin
      [:en, :fr].each do |locale|
        I18n.locale = locale
        raise 'localized palette name changed stylesheet key' unless record.read_attribute(:name) == record.source_raw_palette_name
        raise 'localized palette name changed stylesheet key' unless [source_key(record, nil), source_key(record, theme_id)] == keys
      end
    ensure
      I18n.locale = old
    end
    units = ["A_B ' test--42", '123', ':smile:', 'A' * 280].map { |text| source_slug(text) }
    result = {keys: keys, units: units, hostname: hostname, relative_url_root: root, slug_method: SiteSetting.slug_generation_method, default_locale: SiteSetting.default_locale}
    puts 'FIDELITY_STYLESHEET_KEY ' + JSON.generate(result)
    nil
  end
end
