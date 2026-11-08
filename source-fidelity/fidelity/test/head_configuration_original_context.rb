# frozen_string_literal: true
require_relative 'original_head_configuration_helpers'
class OriginalListBodyContext
  include OriginalHeadConfigurationHelpers
  include HeadConfigurationViewProtocol
  def layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @output_buffer = ActionView::OutputBuffer.new
    begin
      render_application_layout { |slot| head_yield_capability(slot) }
      raise 'original head configuration layout unexpectedly returned'
    ensure
      close_request_assets
    end
  end
  def observation; head_configuration_stage_observation; end
end
