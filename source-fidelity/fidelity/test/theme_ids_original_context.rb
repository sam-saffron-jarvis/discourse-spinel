# frozen_string_literal: true
require_relative 'original_theme_ids_source'
module ThemeIdsRead
  def self.acquire_ids; observe_pluck(::Theme.pluck(:id)); end
  def self.pluck(column)
    raise ArgumentError, 'Theme IDs pluck column' unless column == :id
    acquire_ids
  end
  def self.original_cache; CategoryCacheBootstrap.theme_compiler_cache; end
  def self.source_ids; OriginalRequestThemeIdsSource.theme_ids; end
end
class ObservedOriginalCategoryCache
  alias_method :raw_defer_get_set_before_theme_ids_observation, :defer_get_set
  def defer_get_set(key)
    return raw_defer_get_set_before_theme_ids_observation(key) { yield } unless key == 'theme_ids'
    raw_defer_get_set_before_theme_ids_observation(key) do
      value = yield
      CategoryCacheBootstrap.lease.note_theme_ids(key, value)
      value
    end
  end
  def defer_get_set_ids(key)
    defer_get_set(key) { yield }
  end
end
class OriginalRequestStyleReadManager
  include ThemeIdsStylesheetPrefix
end
class OriginalListBodyContext
  include ThemeIdsViewProtocol
  def observation; theme_ids_stage_observation; end
end
