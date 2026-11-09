# frozen_string_literal: true
require_relative 'stylesheet_manager_read_source'
module StylesheetManagerReadBoundary
  def self.acquire(manager, scheme_id, fallback)
    raise ArgumentError, 'unsupported stylesheet fallback profile' unless fallback == true
    raise TypeError, 'stylesheet selected palette type changed' unless scheme_id.nil? || scheme_id.is_a?(Integer)
    @manager = manager
    @scheme_id = scheme_id
    raise HtmlRenderingBoundary, 'actual stylesheet manager acquired; color stylesheet cache/read capability pending; writes remain prohibited'
  end
  def self.manager; @manager; end
  def self.scheme_id; @scheme_id; end
end
class RequestStyleReadManager
  def color_scheme_stylesheet_link_tag_href(id = nil, fallback_to_base: true)
    @theme_ids = [0] if ENV.fetch('FIDELITY_STYLESHEET_READ_FAULT', '') == 'wrong-theme-ids'
    StylesheetManagerReadBoundary.acquire(self, id, fallback_to_base)
  end
end
module StylesheetManagerReadViewProtocol
  def stylesheet_manager; source_stylesheet_manager; end
  def stylesheet_manager_read_stage_observation
    record = body_layout_stage_observation
    manager = StylesheetManagerReadBoundary.manager
    raise 'stylesheet source manager missing' if manager.nil?
    raise 'stylesheet source manager warm identity changed' unless manager.equal?(source_stylesheet_manager) && manager.equal?(source_stylesheet_manager)
    raise 'stylesheet source constructor theme differs' unless manager.acquired_theme_id == theme_id
    raise 'stylesheet source constructor transformed ids differ' unless manager.acquired_theme_ids == Theme.transform_ids(theme_id)
    raise 'stylesheet source constructor cache not empty' unless manager.acquired_themes_cache.empty?
    raise 'stylesheet source evaluated palette differs' unless StylesheetManagerReadBoundary.scheme_id == scheme_id
    record[:stylesheet_manager_read] = {theme_id: manager.acquired_theme_id, theme_ids: manager.acquired_theme_ids, scheme_id: StylesheetManagerReadBoundary.scheme_id, source_warm_identity: true, constructor_cache_empty: true, stylesheet_cache_registered: false, color_stylesheet_href_acquired: false, stylesheet_acquired: false, effects_attempted: false}
    record
  end
end
class ListBodyContext
  include StylesheetManagerReadSource
  include StylesheetManagerReadViewProtocol
  def observation; stylesheet_manager_read_stage_observation; end
end
