# frozen_string_literal: true
require_relative "category_cache_original_context"
require_relative "list_body_original_context"
require_relative "list_head_original_context"
require "mini_mime"
require_relative "original_list_layout"
class OriginalLayoutEnvironment < SimpleDelegator
  def [](key)
    __getobj__[key == :resolved_theme_id ? "discourse.resolved_theme_id" : key]
  end
end
class OriginalLayoutRequest < SimpleDelegator
  def env; OriginalLayoutEnvironment.new(__getobj__.env); end
end
module OriginalApplicationLayout
  module GlobalSetting
    def self.early_hint_header_mode; ListHeadImages.configuration.value("early_hint_header_mode"); end
  end
end
class OriginalListBodyContext
  include ListLayoutViewProtocol
  include OriginalApplicationLayout
  include OriginalListLayoutHelpers
  def request; OriginalLayoutRequest.new(@controller.request); end
  def cookies
    raise ArgumentError, "unsupported original layout cookies" unless request.env["HTTP_COOKIE"].nil?
    {}
  end
  def content_for(slot)
    return super { yield } if block_given?
    value = case slot
    when :title then @title_output
    when :head then @head_output
    else raise "unknown original content slot"
    end
    value.empty? ? nil : value.html_safe
  end
  def layout_boundary
    raise "layout executed before completed body" unless @body_returned
    @events << "layout_render"
    @output_buffer = ActionView::OutputBuffer.new
    render_application_layout
    raise "original full layout unexpectedly returned"
  end
  def current_page?(path); request.path == path; end
  def use_crawler_layout?; controller.use_crawler_layout?; end
  def layout_fragment(value); value.to_s.html_safe; end
  def observation; layout_stage_observation; end
end

require_relative "list_color_original_context"

require_relative "original_list_canonical"
module OriginalListCanonical
  module ContentLocalization
    def self.crawler_locale_param_enabled?
      SiteSetting.content_localization_enabled && SiteSetting.content_localization_crawler_param && SiteSetting.set_locale_from_param
    end
  end
end
class ListBodyParams
  def select(&block); @values.select(&block); end
end
class OriginalListBodyContext
  include OriginalListCanonical
end
