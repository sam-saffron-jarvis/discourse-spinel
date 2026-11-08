# frozen_string_literal: true
# Only two additional source Theme cache domains; other Array/String guards stay.
class CategoryCacheLease
  def svg_theme_settings_key?(key)
    key.is_a?(String) && /\Asettings_for_theme_-?[0-9]+_(true|false)\z/.match?(key)
  end
  def svg_theme_modifier_key?(key)
    key.is_a?(String) && /\A-?[0-9]+(?:,-?[0-9]+)*:modifier:svg_icons:[a-f0-9]{40}\z/.match?(key)
  end
  def note_svg_theme_value(key, value)
    check!(@host, @port)
    if svg_theme_settings_key?(key)
      raise TypeError, 'nonempty Theme settings Hash profile unacquired' unless value.is_a?(Hash) && value.empty?
    elsif svg_theme_modifier_key?(key)
      raise TypeError, 'Theme SVG modifier result must be String Array' unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    else
      raise ArgumentError, 'unadmitted SVG Theme cache key'
    end
    @lock.synchronize do
      @svg_theme_encodings ||= {}
      @svg_theme_encodings[key] = Base64.encode64(Marshal.dump(value))
    end
    nil
  end
  def admitted_svg_theme_value?(data)
    return false unless data['hash_key'] == theme_cache_key && (svg_theme_settings_key?(data['key']) || svg_theme_modifier_key?(data['key']))
    @lock.synchronize do
      !@svg_theme_encodings.nil? && @svg_theme_encodings.key?(data['key']) && data['marshalled'] == true && @svg_theme_encodings[data['key']] == data['value']
    end
  end
end
module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_svg_theme_settings(key)
      raise ArgumentError, 'unadmitted SVG Theme settings key' unless CategoryCacheBootstrap.lease.svg_theme_settings_key?(key)
      @category_data_monitor.synchronize do
        if hash.key?(key)
          svg_theme_settings_hit(key)
        else
          value = yield
          CategoryCacheBootstrap.lease.note_svg_theme_value(key, value)
          defer_set(key, value)
          value
        end
      end
    end
    def defer_get_set_svg_theme_modifier(key)
      raise ArgumentError, 'unadmitted SVG Theme modifier key' unless CategoryCacheBootstrap.lease.svg_theme_modifier_key?(key)
      @category_data_monitor.synchronize do
        if hash.key?(key)
          value = self[key]
          raise TypeError, 'Theme SVG modifier hit type changed' unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
          value
        else
          value = yield
          CategoryCacheBootstrap.lease.note_svg_theme_value(key, value)
          defer_set(key, value)
          value
        end
      end
    end
    def svg_theme_settings_hit(key)
      raise ArgumentError, 'unadmitted SVG Theme settings hit' unless CategoryCacheBootstrap.lease.svg_theme_settings_key?(key)
      value = self[key]
      raise TypeError, 'nonempty Theme settings Hash profile unacquired' unless value.is_a?(Hash) && value.empty?
      value
    end
  end
end
