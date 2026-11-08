# frozen_string_literal: true
# UNIT-only direct original leaf producers with genuine readonly PG rows.
# Never called as a fake preload or used to seed a request fixture.
module SvgIconsReadUnit
  def self.wait_for(cache, key)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    until cache.svg_values.key?(key)
      raise 'SVG icon publication missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end
  def self.run
    lease = CategoryCacheBootstrap.lease
    RequestSvgBootstrap.bind([])
    badges = RequestSvgBootstrap.badge_icons
    groups = RequestSvgBootstrap.group_icons
    cache = CategoryCacheBootstrap.svg_cache
    wait_for(cache, 'badge_icons')
    wait_for(cache, 'group_icons')
    raise 'SVG badge original query differs' unless badges == Badge.pluck(:icon).uniq
    raise 'SVG group original query differs' unless groups == Group.pluck(:flair_icon).uniq
    before = lease.publication_count
    warm_badges = RequestSvgBootstrap.badge_icons
    warm_groups = RequestSvgBootstrap.group_icons
    raise 'SVG actual warm hit changed identity' unless warm_badges.equal?(badges) && warm_groups.equal?(groups)
    raise 'SVG warm hit republished' unless lease.publication_count == before
    begin
      cache.defer_get_set_svg_icons('settings_icons') { raise ArgumentError, 'UNIT SVG producer error' }
      raise 'SVG producer exception swallowed'
    rescue ArgumentError => error
      raise unless error.message == 'UNIT SVG producer error'
    end
    raise 'SVG failed producer populated cache' if cache.svg_values.key?('settings_icons')
    begin
      cache.defer_get_set_svg_icons('settings_icons') { JSON.parse('[12345]') }
      raise 'SVG wrong result type accepted'
    rescue TypeError => error
      raise unless error.message == 'SVG icon computation type' || error.message == 'SVG icon result type'
    end
    raise 'SVG failed producer dispatched' unless lease.publication_count == before && cache.svg_values.size == 2
    puts 'FIDELITY_SVG_ICONS_UNIT ' + JSON.generate({unit_only: true, badges: badges, groups: groups, contains_real_null: groups.include?(nil), warm_identity: true, producer_exception_propagated: true, invalid_type_refused: true, values: cache.svg_values})
  end
end
SvgIconsReadUnit.run
