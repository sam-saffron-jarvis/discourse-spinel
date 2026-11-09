# frozen_string_literal: true
module ThemeIdsRead
  def self.check_key(key)
    lease = CategoryCacheBootstrap.lease
    fault = ENV.fetch('FIDELITY_THEME_IDS_FAULT', '')
    if fault == 'wrong-runtime'
      begin
        lease.instance_variable_set(:@runtime_pid, Process.pid + 1)
        lease.check!(lease.host, lease.port)
      ensure
        # Restore only TEST mutation for existing real subscription cleanup.
        lease.instance_variable_set(:@runtime_pid, Process.pid)
      end
    end
    lease.check!(lease.host, fault == 'shared-endpoint' ? 6399 : (fault == 'unknown-endpoint' ? 1 : lease.port))
    raise ArgumentError, 'Theme ID cache key' unless key.is_a?(String) && key == 'theme_ids'
    nil
  end
  def self.check_value(value)
    raise TypeError, 'Theme IDs require Integer Array' unless value.is_a?(Array) && value.all? { |id| id.is_a?(Integer) }
    raise TypeError, 'Theme IDs source Array unexpectedly frozen' if value.frozen?
    nil
  end
  def self.acquire_ids
    value = ::Theme.pluck(:id)
    observe_pluck(value)
  end
  def self.observe_pluck(value)
    @queries = queries + 1
    check_value(['invalid-integer']) if ENV.fetch('FIDELITY_THEME_IDS_FAULT', '') == 'wrong-type'
    check_value(value)
    @computed_json ||= []
    @computed_json << JSON.generate(value)
    value
  end
  def self.queries; @queries || 0; end
  def self.computed_json; @computed_json || []; end
  def self.source_ids; RequestThemeIdsSource.theme_ids; end
  def self.note_consumer(id)
    @consumed_json ||= []
    @consumed_json << JSON.generate(id)
    nil
  end
  def self.consumed_json; @consumed_json || []; end
  def self.verify_warm(cache, value)
    check_value(value)
    before = queries
    before_publications = CategoryCacheBootstrap.lease.publication_count
    first = source_ids
    second = source_ids
    raise 'Theme IDs warm cache identity changed' unless first.equal?(value) && second.equal?(value)
    raise 'Theme IDs warm cache re-queried' unless queries == before
    raise 'Theme IDs warm cache republished' unless before_publications == CategoryCacheBootstrap.lease.publication_count
    raise 'Theme IDs actual acquired value changed' unless computed_json.include?(JSON.generate(value))
    puts 'FIDELITY_THEME_ID_CACHE ' + JSON.generate({ids: value, integer_array: true, mutable: !value.frozen?, acquisitions: queries, computed_vectors_json: computed_json, warm_identity: true, warm_requeried: false, consumer_theme_ids_json: consumed_json})
    nil
  end
end
class CategoryCacheLease
  def note_theme_ids(key, value)
    check!(@host, @port)
    ThemeIdsRead.check_key(key)
    ThemeIdsRead.check_value(value)
    @theme_ids_encodings ||= []
    @theme_ids_encodings << Base64.encode64(Marshal.dump(value))
    nil
  end
  def admitted_theme_ids_value?(data)
    data['hash_key'] == theme_cache_key && data['key'] == 'theme_ids' && !@theme_ids_encodings.nil? && data['marshalled'] == true && data['value'].is_a?(String) && @theme_ids_encodings.include?(data['value'])
  end
end
