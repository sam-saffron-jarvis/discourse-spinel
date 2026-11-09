# frozen_string_literal: true
require_relative 'original_client_meta_palette'
require_relative 'original_client_meta_layout'
module OriginalClientSetupHelpers
  module GlobalSetting
    def self.enable_js_error_reporting; ClientMetaRead.error_reporting; end
  end
  module SiteSetting
    def self.default_locale; ::SiteSetting.default_locale; end
    def self.Upload; ClientMetaUploadRead; end
  end
  module MessageBus
    def self.last_id(channel); ClientMetaRead.last_id(channel); end
  end
  module SvgSprite
    def self.all_icons(id); ClientMetaRead.all_icons(id); end
  end
end
module OriginalClientMetaLayoutBoundary
  def original_client_meta_layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @output_buffer = ActionView::OutputBuffer.new
    begin
      render_application_layout { |slot| head_yield_capability(slot) }
      @events << 'client_setup_meta_returned'
      raise HtmlRenderingBoundary, 'actual client setup meta consumer returned; remaining layout acquisition pending'
    ensure
      close_request_assets
    end
  end
end
class OriginalListBodyContext
  include OriginalClientMetaLayout
  include ClientMetaViewProtocol
  include OriginalClientMetaPalette
  include OriginalClientMetaLayoutBoundary
  def layout_boundary; original_client_meta_layout_boundary; end
  def observation; client_meta_stage_observation; end
end
