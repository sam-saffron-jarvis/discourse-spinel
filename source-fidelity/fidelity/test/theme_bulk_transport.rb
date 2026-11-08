# frozen_string_literal: true
# Additional owned Theme-field domain only. Existing String/extra_js guards stay.
class CategoryCacheLease
  def theme_field_key?(key)
    !theme_cache_key.nil? && key.is_a?(String) && /\A-?[0-9]+:translations:[A-Za-z_-]+:[a-f0-9]{40}\z/.match?(key)
  end
  def note_theme_field_value(key, value)
    raise ArgumentError, 'unadmitted Theme field key' unless theme_field_key?(key)
    raise TypeError, 'Theme field result type' unless value.nil? || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
    @lock.synchronize do
      @theme_field_encodings ||= {}
      @theme_field_encodings[key] = value.nil? ? nil : Base64.encode64(Marshal.dump(value))
    end
    nil
  end
  def note_bulk_enqueue(count)
    @lock.synchronize do
      @field_bulk_jobs = field_bulk_jobs + 1
      @field_bulk_members = field_bulk_members + count
    end
    nil
  end
  def field_bulk_jobs; @field_bulk_jobs ||= 0; end
  def field_bulk_members; @field_bulk_members ||= 0; end
  def admitted_field_value?(data)
    key = data['key']
    return false unless data['hash_key'] == theme_cache_key && theme_field_key?(key)
    @lock.synchronize do
      return false unless !@theme_field_encodings.nil? && @theme_field_encodings.key?(key)
      encoded = @theme_field_encodings[key]
      encoded.nil? ? (data['marshalled'] == false && data['value'].nil?) : (data['marshalled'] == true && data['value'] == encoded)
    end
  end
end
