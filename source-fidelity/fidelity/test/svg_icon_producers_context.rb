# frozen_string_literal: true
require_relative 'svg_icon_producers_metadata'
require_relative 'svg_icon_producers_source'
module SvgIconProducers
  def self.cached_on_entry; @cached_on_entry; end
  def self.note_entry; @cached_on_entry = CategoryCacheBootstrap.svg_cache.svg_values.key?('settings_icons'); nil; end
  def self.note_settings_input(value)
    icons = []
    value.each do |key, text|
      icons |= text.split('|') if key.to_s.include?('_icon') || SvgSettingsRead.definition(key.to_s).data_type == 32
    end
    @expected_settings_icons = icons
    nil
  end
  def self.expected_settings_icons; @expected_settings_icons; end
  def self.types; @types ||= SvgIconReadTypes.new; end
  def self.wait_for_values
    cache = CategoryCacheBootstrap.svg_cache
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    until %w[settings_icons badge_icons group_icons].all? { |key| cache.svg_values.key?(key) }
      raise 'SVG producer publications missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    nil
  end
  def self.source_settings_icons; RequestSvgSource.settings_icons; end
  def self.source_badge_icons; RequestSvgSource.badge_icons; end
  def self.source_group_icons; RequestSvgSource.group_icons; end
end
module RequestSvgBootstrap
  def self.path(id)
    SvgIconProducers.note_entry
    RequestSvgSource.path(id)
  end
  def self.settings_hash
    events = @events
    raise 'SVG events not bound' unless events.is_a?(Array)
    events << 'svg_settings_hash_acquisition'
    value = SvgSettingsRead.settings_hash
    SvgSnapshotRead.capture(value)
    SvgIconProducers.note_settings_input(value)
    # CONTROL-only repeated real consumer: normal SVG warm hits intentionally
    # bypass the getter; still exercise the inherited getter memoization fault.
    if ENV.fetch('FIDELITY_SVG_UPLOADED_LIST_FAULT', '') == 'memoized-empty'
      SvgSettingsRead.settings_hash
    end
    value
  end
end
module SvgCacheViewProtocol
  def expected_body_events
    values = expected_client_highlight_events + ['svg_cache_version_acquisition', 'svg_cache_icons_acquisition', 'svg_cache_settings_acquisition']
    values << 'svg_settings_hash_acquisition' unless SvgIconProducers.cached_on_entry
    values
  end
  def svg_cache_stage_observation
    record = client_highlight_stage_observation
    SvgIconProducers.wait_for_values
    cache = CategoryCacheBootstrap.svg_cache
    values = cache.svg_values
    raise 'SVG producer cache keys changed' unless values.keys.sort == %w[badge_icons group_icons settings_icons]
    before = CategoryCacheBootstrap.lease.publication_count
    RequestSvgBootstrap.bind([])
    begin
      settings = SvgIconProducers.source_settings_icons
      badges = SvgIconProducers.source_badge_icons
      groups = SvgIconProducers.source_group_icons
    ensure
      RequestSvgBootstrap.bind(@events)
    end
    raise 'SVG settings producer source input changed' unless settings == SvgIconProducers.expected_settings_icons
    raise 'SVG settings producer warm identity changed' unless settings.equal?(values['settings_icons'])
    raise 'SVG badge producer warm identity changed' unless badges.equal?(values['badge_icons'])
    raise 'SVG group producer warm identity changed' unless groups.equal?(values['group_icons'])
    raise 'SVG warm producers republished' unless before == CategoryCacheBootstrap.lease.publication_count
    raise 'SVG badge actual readonly rows changed' unless badges == Badge.pluck(:icon).uniq
    raise 'SVG group actual readonly rows changed' unless groups == Group.pluck(:flair_icon).uniq
    id_key = ListThemeCompilerSource.transform_ids(theme_id).join(',')
    cold = ["version_#{id_key}:miss", "icons_#{id_key}:miss", 'settings_icons:miss', 'badge_icons:miss', 'group_icons:miss', 'settings_icons:hit', 'badge_icons:hit', 'group_icons:hit']
    warm = ["version_#{id_key}:miss", "icons_#{id_key}:miss", 'settings_icons:hit', 'badge_icons:hit', 'group_icons:hit', 'settings_icons:hit', 'badge_icons:hit', 'group_icons:hit']
    notes = RequestSvgBootstrap.notes
    raise 'SVG producer source cache order changed' unless notes == cold || notes == cold + warm
    raise 'SVG cache manager registration missing' unless CategoryCacheBootstrap.manager.subscribers.size == 5
    record[:svg_cache] = {notes: notes, values: values, registered: true, source_getter_returned: true}
    record
  end
end
module SvgIconProducersViewProtocol
  def svg_icon_producers_stage_observation
    record = svg_objects_stage_observation
    cache = CategoryCacheBootstrap.svg_cache.svg_values
    record[:svg_icon_producers] = {settings_icons: cache['settings_icons'], badge_icons: cache['badge_icons'], group_icons: cache['group_icons'], real_nullable_group_icon: cache['group_icons'].include?(nil), warm_identity: true, warm_republished: false, remaining_theme_icons_acquired: false}
    record
  end
end
class ListBodyContext
  include SvgIconProducersViewProtocol
  def observation; svg_icon_producers_stage_observation; end
end
