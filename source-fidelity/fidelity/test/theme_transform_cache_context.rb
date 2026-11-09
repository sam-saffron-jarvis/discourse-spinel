# frozen_string_literal: true
require_relative 'theme_transform_cache_source'
module ThemeTransformRead
  def self.configure(id)
    raise ArgumentError, 'transform cache requires actual Integer theme ID' unless id.is_a?(Integer)
    @theme_id = id
    @computed = {}
    @acquisitions = {}
    nil
  end
  def self.key?(key)
    key.is_a?(String) && ['parent_theme_ids', "theme_components_for_#{@theme_id}", "transformed_ids_#{@theme_id}"].include?(key)
  end
  def self.check_key(key)
    return ThemeIdsRead.check_key(key) unless key?(key)
    lease = CategoryCacheBootstrap.lease
    lease.check!(lease.host, lease.port)
    raise ArgumentError, 'Theme transform cache key' unless key?(key)
    nil
  end
  def self.observe(key, value)
    check_key(key)
    ThemeIdsRead.check_value(['bad-transform-id']) if ENV.fetch('FIDELITY_TRANSFORM_IDS_FAULT', '') == 'wrong-type'
    ThemeIdsRead.check_value(value)
    @acquisitions[key] = (@acquisitions[key] || 0) + 1
    @computed[key] ||= []
    @computed[key] << JSON.generate(value)
    nil
  end
  def self.source_transform(id); RequestThemeTransformSource.transform_ids(id); end
  def self.source_parent; RequestThemeTransformSource.parent_theme_ids; end
  def self.source_components(id); RequestThemeTransformSource.components_for(id); end
  def self.source_parent?(id); RequestThemeTransformSource.is_parent_theme?(id); end
  def self.source_for(key)
    return source_parent if key == 'parent_theme_ids'
    return source_components(@theme_id) if key == "theme_components_for_#{@theme_id}"
    return source_transform(@theme_id) if key == "transformed_ids_#{@theme_id}"
    raise ArgumentError, 'Theme transform cache key'
  end
  def self.acquire
    source_transform(@theme_id)
    source_transform(@theme_id)
    source_parent
    source_components(@theme_id)
    source_for('unowned-transform-key') if ENV.fetch('FIDELITY_TRANSFORM_IDS_FAULT', '') == 'wrong-key'
    nil
  end
  def self.verify_warm(key, value)
    ThemeIdsRead.check_value(value)
    before = JSON.generate(@acquisitions)
    publications = CategoryCacheBootstrap.lease.publication_count
    first = source_for(key)
    second = source_for(key)
    puts 'FIDELITY_TRANSFORM_IDENTITY_DIAGNOSTIC ' + JSON.generate({key: key, first: first.object_id, second: second.object_id, cached: value.object_id, first_same: first.equal?(value), second_same: second.equal?(value)}) if ENV.fetch('FIDELITY_TRANSFORM_DIAGNOSTIC', '') == '1'
    raise 'Theme transform warm identity changed' unless first.equal?(value) && second.equal?(value)
    raise 'Theme transform warm re-queried' unless before == JSON.generate(@acquisitions)
    raise 'Theme transform warm republished' unless publications == CategoryCacheBootstrap.lease.publication_count
    raise 'Theme transform actual vector changed' unless @computed[key].include?(JSON.generate(value))
    puts 'FIDELITY_THEME_TRANSFORM_CACHE ' + JSON.generate({key: key, ids: value, warm_identity: true, computed_vectors_json: @computed[key], acquisitions: @acquisitions[key], readonly_source: true})
    nil
  end
end
class Theme
  def self.transform_ids(id); ThemeTransformRead.source_transform(id); end
  def self.parent_theme_ids; ThemeTransformRead.source_parent; end
  def self.is_parent_theme?(id); ThemeTransformRead.source_parent?(id); end
  def self.components_for(id); ThemeTransformRead.source_components(id); end
end
class CategoryCacheLease
  def note_transform_ids(key, value)
    check!(@host, @port)
    ThemeTransformRead.observe(key, value)
    @transform_encodings ||= {}
    @transform_encodings[key] ||= []
    @transform_encodings[key] << Base64.encode64(Marshal.dump(value))
    nil
  end
  def admitted_transform_ids_value?(data)
    key = data['key']
    return false unless data['hash_key'] == theme_cache_key && ThemeTransformRead.key?(key) && data['marshalled'] == true && data['value'].is_a?(String) && !@transform_encodings.nil?
    encodings = @transform_encodings[key]
    !encodings.nil? && encodings.include?(data['value'])
  end
end
