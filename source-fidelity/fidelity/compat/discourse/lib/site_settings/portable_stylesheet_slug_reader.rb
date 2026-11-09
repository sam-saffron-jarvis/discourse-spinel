# frozen_string_literal: true
# Exact no-wrap SlugSetting GETTER contract, not scalar/enum admission in general.
require_relative 'portable_read_store'
module SiteSettings
  class PortableReadStore
    def stylesheet_slug_current(site)
      definition = @definitions['slug_generation_method']
      raise PortableUnsupported, 'stylesheet SlugSetting declaration changed' unless definition && definition.data_type == 1 && definition.options['enum'] == 'SlugSetting'
      options = definition.options
      forbidden = %w[themeable plugin upcoming_change upcoming_change_default_override portable_source_override mandatory_values]
      raise PortableUnsupported, 'unsupported stylesheet SlugSetting callback profile' if forbidden.any? { |key| options.key?(key) }
      snapshot = @mutex.synchronize { @values[site] }
      if snapshot.nil? || snapshot['slug_generation_method'].nil?
        refresh!(site)
        snapshot = @mutex.synchronize { @values[site] }
      end
      value = snapshot['slug_generation_method']
      raise PortableUnsupported, 'stylesheet SlugSetting must remain String' unless value.is_a?(String)
      value
    end
  end
end
