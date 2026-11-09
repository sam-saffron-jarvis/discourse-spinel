# frozen_string_literal: true
# Real source nil theme-sprite bulk entries and version Strings, separate domains.
class CategoryCacheLease
  def svg_sprite_nil_key?(key)
    key.is_a?(String) && /\Atheme_svg_sprites_-?[0-9]+\z/.match?(key)
  end
  def note_svg_sprite_value(key, value)
    check!(@host, @port)
    raise ArgumentError, 'unadmitted Theme SVG sprite key' unless svg_sprite_nil_key?(key)
    value = {} if ENV.fetch('FIDELITY_SVG_BUNDLE_FAULT', '') == 'nonempty-sprite'
    raise ArgumentError, 'nonempty Theme SVG sprite profile unacquired' unless value.nil?
    @lock.synchronize do
      @svg_sprite_nil_values ||= {}
      @svg_sprite_nil_values[key] = true
    end
    nil
  end
  def note_svg_version(key, value)
    check!(@host, @port)
    raise ArgumentError, 'unadmitted SVG version key' unless key.is_a?(String) && /\Aversion_-?[0-9]+(?:,-?[0-9]+)*\z/.match?(key)
    raise TypeError, 'SVG version result type changed' unless value.is_a?(String) && /\A[a-f0-9]{40}\z/.match?(value)
    @lock.synchronize do
      @svg_versions ||= {}
      @svg_versions[key] = value
    end
    nil
  end
  def admitted_svg_bundle_value?(data)
    return false unless data['hash_key'] == 'svg_sprite' && data['marshalled'] == false
    @lock.synchronize do
      key = data['key']
      if svg_sprite_nil_key?(key)
        !@svg_sprite_nil_values.nil? && @svg_sprite_nil_values[key] == true && data['value'].nil?
      else
        !@svg_versions.nil? && @svg_versions.key?(key) && @svg_versions[key] == data['value']
      end
    end
  end
  def note_svg_bulk_enqueue(count)
    @lock.synchronize do
      @svg_bulk_jobs = svg_bulk_jobs + 1
      @svg_bulk_members = svg_bulk_members + count
    end
    nil
  end
  def svg_bulk_jobs; @svg_bulk_jobs || 0; end
  def svg_bulk_members; @svg_bulk_members || 0; end
end
