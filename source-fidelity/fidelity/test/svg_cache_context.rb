# frozen_string_literal: true
require_relative 'svg_cache_source'
module ClientHighlightBootstrap
  def self.events; @events; end
end
module RequestSvgBootstrap
  def self.bind(events)
    @events = events
    @notes ||= []
    nil
  end
  def self.notes; @notes ||= []; end
  def self.note_cache(key, cache)
    present = cache.svg_values.key?(key)
    notes << "#{key}:#{present ? 'hit' : 'miss'}"
    events = @events
    if events.is_a?(Array)
      events << 'svg_cache_version_acquisition' if key.start_with?('version_')
      events << 'svg_cache_icons_acquisition' if key.start_with?('icons_')
      events << 'svg_cache_settings_acquisition' if key == 'settings_icons'
    end
    nil
  end
  def self.settings_hash
    events = @events
    raise 'SVG events not bound' unless events.is_a?(Array)
    events << 'svg_settings_hash_acquisition'
    raise HtmlRenderingBoundary, 'actual SVG version/icons/settings cache misses acquired; source settings_hash getter acquisition pending'
  end
  def self.path(id); RequestSvgSource.path(id); end
  def self.badge_icons; RequestSvgSource.badge_icons; end
  def self.group_icons; RequestSvgSource.group_icons; end
end
module SvgCacheViewProtocol
  def client_setup_svg_path(id)
    @events << 'svg_sprite_acquisition'
    RequestSvgBootstrap.bind(@events)
    RequestSvgBootstrap.path(id)
  end
  def expected_body_events
    expected_client_highlight_events + ['svg_cache_version_acquisition', 'svg_cache_icons_acquisition', 'svg_cache_settings_acquisition', 'svg_settings_hash_acquisition']
  end
  def svg_cache_stage_observation
    record = client_highlight_stage_observation
    cache = CategoryCacheBootstrap.svg_cache
    raise 'SVG cache unexpectedly populated after failed source computation' unless cache.svg_values.empty?
    id_key = ListThemeCompilerSource.transform_ids(theme_id).join(',')
    notes = RequestSvgBootstrap.notes
    expected = ["version_#{id_key}:miss", "icons_#{id_key}:miss", 'settings_icons:miss']
    raise 'SVG source cache order changed' unless notes.each_slice(3).all? { |slice| slice == expected }
    raise 'SVG cache manager registration missing' unless CategoryCacheBootstrap.manager.subscribers.size == 5
    record[:svg_cache] = {notes: notes, values: cache.svg_values, registered: true, source_getter_returned: false}
    record
  end
end
class ListBodyContext
  include SvgCacheViewProtocol
  def observation; svg_cache_stage_observation; end
end
