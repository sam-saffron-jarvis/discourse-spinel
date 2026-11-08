# frozen_string_literal: true
class CategoryCacheLease
  def svg_key?(key)
    key.is_a?(String) && (['badge_icons', 'group_icons', 'settings_icons'].include?(key) || /\A(?:icons|version)_-?[0-9]+(?:,-?[0-9]+)*\z/.match?(key))
  end
  def note_svg_icons(key, value)
    check!(@host, @port)
    raise ArgumentError, 'unadmitted SVG icon key' unless svg_key?(key) && !key.start_with?('version_')
    raise TypeError, 'SVG icon result type' unless value.is_a?(Array) && value.all? { |item| item.nil? || item.is_a?(String) }
    @lock.synchronize do
      @svg_encodings ||= {}
      @svg_encodings[key] = Base64.encode64(Marshal.dump(value))
    end
    nil
  end
  def admitted_svg_value?(data)
    return false unless data['hash_key'] == 'svg_sprite' && svg_key?(data['key'])
    @lock.synchronize do
      !@svg_encodings.nil? && @svg_encodings.key?(data['key']) && data['marshalled'] == true && @svg_encodings[data['key']] == data['value']
    end
  end
end
module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_svg_icons(key)
      raise ArgumentError, 'SVG icon cache key' unless CategoryCacheBootstrap.lease.svg_key?(key) && !key.start_with?('version_')
      @category_data_monitor.synchronize do
        if hash.key?(key)
          value = self[key]
          raise TypeError, 'SVG icon hit type' unless value.is_a?(Array) && value.all? { |item| item.nil? || item.is_a?(String) }
          value
        else
          value = yield
          raise TypeError, 'SVG icon computation type' unless value.is_a?(Array) && value.all? { |item| item.nil? || item.is_a?(String) }
          CategoryCacheBootstrap.lease.note_svg_icons(key, value)
          defer_set(key, value)
          value
        end
      end
    end
    def svg_values; @category_data_monitor.synchronize { hash.dup }; end
  end
end
module CategoryCacheBootstrap
  def self.svg_cache_values
    cache = @acquired_svg_cache
    cache.nil? ? {} : cache.svg_values
  end
  def self.svg_cache
    @acquired_svg_cache ||= CategoryCacheApplication::DistributedCache.new('svg_sprite', manager: manager)
  end
end
