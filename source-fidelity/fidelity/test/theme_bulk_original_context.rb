# frozen_string_literal: true
class ObservedOriginalCategoryCache
  def defer_get_set_fields(keys, key_block)
    defer_get_set_bulk(keys, key_block) do |missing|
      values = yield missing
      missing.zip(values).each { |key, value| CategoryCacheBootstrap.lease.note_theme_field_value(key_block.call(key), value) }
      CategoryCacheBootstrap.lease.note_bulk_enqueue(missing.size)
      values
    end
  end
  def theme_field_present?(key); hash.key?(key); end
  def theme_field_hit(key)
    raise 'Theme field cache key outside lease' unless CategoryCacheBootstrap.lease.theme_field_key?(key)
    value = hash.fetch(key)
    raise TypeError, 'Theme field cache value type' unless value.nil? || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
    value
  end
end
