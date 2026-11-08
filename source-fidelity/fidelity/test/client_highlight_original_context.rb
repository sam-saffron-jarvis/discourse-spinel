# frozen_string_literal: true
require_relative 'original_client_highlight_source'
require_relative 'original_client_loading_admin_source'
module ClientHighlightBootstrap
  def self.source_path; OriginalRequestHighlightJs.path; end
  def self.source_version(languages); OriginalRequestHighlightJs.version(languages); end
  def self.source_cache; OriginalRequestHighlightJs.cache; end
end
module OriginalClientSetupHelpers
  module HighlightJs
    def self.path; ClientHighlightBootstrap.path; end
  end
  module SvgSprite
    def self.path(id)
      ClientHighlightBootstrap.pending_svg
    end
  end
end
module ClientHighlightBootstrap
  def self.pending_svg
    events = @events
    raise 'HighlightJs events not bound' unless events.is_a?(Array)
    events << 'svg_sprite_acquisition'
    raise HtmlRenderingBoundary, 'actual loading-admin and HighlightJs path acquired; SVG sprite acquisition pending'
  end
end
class OriginalListBodyContext
  include OriginalClientLoadingAdminSource
  include ClientHighlightViewProtocol
  def observation; client_highlight_stage_observation; end
end
