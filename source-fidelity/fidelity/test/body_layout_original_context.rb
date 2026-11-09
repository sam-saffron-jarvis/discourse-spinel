# frozen_string_literal: true
require_relative 'original_body_layout_source'
require_relative 'original_body_layout_template'
require_relative 'original_body_splash_template'
module BodyLayoutRead
  def self.source_upload
    view = OriginalSvgSettingsReference.instance_variable_get(:@view)
    raise 'raw original settings getter view missing' if view.nil?
    view.public_send(:splash_screen_image)
  end
end
class OriginalBodyLayoutCookies < SimpleDelegator
  def [](key)
    BodyLayoutRead.note_cookie(key)
    __getobj__[key]
  end
end
module OriginalBodyLayoutBoundary
  def original_body_cookies
    raise ArgumentError, 'unsupported original layout cookies' unless request.env['HTTP_COOKIE'].nil?
    @original_body_cookies ||= OriginalBodyLayoutCookies.new({})
  end
  def original_body_layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @output_buffer = ActionView::OutputBuffer.new
    begin
      render_application_layout { |slot| head_yield_capability(slot) }
      raise 'original body layout stylesheet boundary unexpectedly returned'
    ensure
      close_request_assets
    end
  end
  def u(value)
    ERB::Util.url_encode(value)
  end
end
class OriginalListBodyContext
  include OriginalBodySplashTemplate
  include OriginalBodyLayoutSource
  include OriginalBodyLayoutTemplate
  include BodyLayoutViewProtocol
  include OriginalBodyLayoutBoundary
  # Keep raw source color methods above the candidate view adapters.
  def light_color_hex_for_name(name); OriginalListColors.hex_for_name(name, scheme_id); end
  def dark_color_hex_for_name(name); OriginalListColors.hex_for_name(name, dark_scheme_id); end
  def cookies; original_body_cookies; end
  def layout_boundary; original_body_layout_boundary; end
  def observation; body_layout_stage_observation; end
end
