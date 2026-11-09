# frozen_string_literal: true
require_relative 'original_stylesheet_manager_read_source'
class OriginalRequestStyleReadManager
  def color_scheme_stylesheet_link_tag_href(id = nil, fallback_to_base: true)
    StylesheetManagerReadBoundary.acquire(self, id, fallback_to_base)
  end
end
class OriginalListBodyContext
  include OriginalStylesheetManagerReadSource
  include StylesheetManagerReadViewProtocol
  def observation; stylesheet_manager_read_stage_observation; end
end
