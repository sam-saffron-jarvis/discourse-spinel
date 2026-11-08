# frozen_string_literal: true
# Explicit UNIT producer only: never application ThemeField/cache inputs.
module ThemeBulkUnit
  def self.wait_for(cache, key)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    until cache.theme_field_present?(key)
      raise 'bulk publication missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end
  def self.run
    CategoryCacheBootstrap.body_icon_cache
    CategoryCacheBootstrap.layout_color_cache
    cache = CategoryCacheBootstrap.theme_compiler_cache
    version = ListThemeCompilerSource.compiler_version
    key_block = lambda { |tuple| "#{tuple[0]}:#{tuple[1]}:#{tuple[2]}:#{version}" }
    one = [-987654, :translations, :en]
    two = [-987654, :translations, :fr]
    three = [-987654, :translations, :de]
    keys = [one, two]
    started = Queue.new
    release = Queue.new
    # Real source worker, held by an explicitly UNIT-only barrier job. No fake
    # queue, synchronous mode, artificial cache seeding or publication result.
    CategoryCacheBootstrap.lease.note_bulk_enqueue(0)
    CategoryCacheBootstrap.scheduler.later("#{cache.key}_bulk_set") do
      started << true
      release.pop
    end
    started.pop
    before = CategoryCacheBootstrap.lease.publication_count
    begin
      cold = cache.defer_get_set_fields(keys, key_block) do |missing|
        raise 'bulk missing slice is not frozen' unless missing.frozen?
        raise 'bulk missing tuple order changed' unless missing == keys
        raise 'bulk caller keys unexpectedly frozen' if keys.frozen?
        [nil, ['UNIT-only-fr']]
      end
      raise 'bulk result tuple order changed' unless cold.keys == keys && cold.values == [nil, ['UNIT-only-fr']]
      raise 'bulk publication was not deferred' unless CategoryCacheBootstrap.lease.publication_count == before && !cache.theme_field_present?(key_block.call(one)) && !cache.theme_field_present?(key_block.call(two))
    ensure
      release << true
    end
    wait_for(cache, key_block.call(one))
    wait_for(cache, key_block.call(two))
    warm = cache.defer_get_set_fields([two, one], key_block) { |_missing| raise 'genuine bulk nil/warm hit recomputed' }
    raise 'bulk warm tuple order/value changed' unless warm.keys == [two, one] && warm.values == [['UNIT-only-fr'], nil]
    mixed = cache.defer_get_set_fields([three, one, two], key_block) do |missing|
      raise 'bulk mixed missing frozen/order changed' unless missing.frozen? && missing == [three]
      [['UNIT-only-de']]
    end
    raise 'bulk mixed return ordering changed' unless mixed.keys == [three, one, two] && mixed.values == [['UNIT-only-de'], nil, ['UNIT-only-fr']]
    wait_for(cache, key_block.call(three))
    empty = cache.defer_get_set_fields([], key_block) { |_missing| raise 'empty bulk invoked producer' }
    raise 'empty bulk result changed' unless empty == {}
    jobs_before = CategoryCacheBootstrap.lease.field_bulk_jobs
    begin
      cache.defer_get_set_fields([[-987654, :translations, :es]], key_block) { |_missing| raise ArgumentError, 'UNIT producer failure' }
      raise 'bulk computation exception swallowed'
    rescue ArgumentError => error
      raise unless error.message == 'UNIT producer failure'
    end
    raise 'bulk exception published missing values' unless jobs_before == CategoryCacheBootstrap.lease.field_bulk_jobs
    puts 'FIDELITY_THEME_BULK_UNIT ' + JSON.generate({unit_only: true, cold_keys: cold.keys, cold_values: cold.values, warm_keys: warm.keys, warm_values: warm.values, mixed_keys: mixed.keys, mixed_values: mixed.values, frozen_missing_slice: true, caller_unfrozen: !keys.frozen?, nil_hit_recomputed: false, deferred_publication_observed: true, computation_exception_propagated: true})
  end
end
ThemeBulkUnit.run
