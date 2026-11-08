# frozen_string_literal: true
require_relative "list_layout_source"
require_relative "native_list_layout"
module ListLayoutViewProtocol
  def layout_boundary
    raise "layout executed before completed body" unless @body_returned
    @events << "layout_render"
    @body_output = +""
    @output_buffer = self
    render_application_layout
    raise "layout prefix unexpectedly returned"
  end
  def list_icon_mime(url)
    extension = File.extname(url).delete_prefix(".")
    types = JSON.parse(File.read(File.join(Rails.root.to_s, "config/list_mime_types.json")))
    value = types[extension] || types[extension.downcase]
    value.nil? ? "image/png" : value.to_s
  end
  def html_lang; I18n.locale.to_s.sub("_", "-"); end
  def html_classes
    list = []
    list << "rtl" if ListLayoutSource::RTL_LOCALES.include?(I18n.locale.to_s)
    list << text_size_class
    list << "anon" unless current_user
    value = @controller.instance_variable_get(:@embed_class)
    list << value unless ActiveSupport.blank?(value)
    list.join(" ")
  end
  def text_size_class
    raise ArgumentError, "unsupported layout cookie/user text-size profile" unless current_user.nil? && request.env["HTTP_COOKIE"].nil?
    "text-size-#{SiteSetting.default_text_size}"
  end
  def customization_disabled?; request.env[ApplicationController::NO_THEMES]; end
  def theme_id
    customization_disabled? ? nil : request.env["discourse.resolved_theme_id"]
  end
  def current_homepage; HomepageHelper.resolve(request, current_user); end
  def title_content
    value = @title_output.empty? ? SiteSetting.title : ActionView::HtmlFragment.new(@title_output)
    DiscoursePluginRegistry.apply_modifier(:meta_data_content, value, :title, {url: request.fullpath})
  end
  def description_content
    DiscoursePluginRegistry.apply_modifier(:meta_data_content, @description_meta || SiteSetting.site_description, :description, {url: request.fullpath})
  end
  def layout_fragment(value); ActionView::HtmlFragment.new(value.to_s); end
  def render(name = nil, partial: nil, opts: nil)
    if name == "layouts/plugin_js"
      @events << "layout_importmap_boundary"
      raise HtmlRenderingBoundary, "actual layout head complete; original plugin/core import-map asset acquisition pending, not a permission barrier"
    end
    raise HtmlRenderingBoundary, "original early stylesheet preload requires guarded stylesheet effect acquisition" if partial == "common/discourse_preload_stylesheet"
    raise ArgumentError, "unknown layout partial" unless partial == "layouts/head"
    @events << "layout_head_partial"
    value = capture_list_body { render_head_partial }
    @events << "layout_head_returned"
    layout_fragment(value)
  end
  def discourse_theme_color_meta_tags
    @events << "layout_color_cache_boundary"
    raise HtmlRenderingBoundary, "original layout color helper requires source-owned scheme_hex_for_name cache acquisition; not a PG permission barrier"
  end
  def expected_body_events
    ["template_lookup", "layout_lookup", "view_flow_receiver", "body_template", "view_flow_set", "layout_render", "layout_head_partial", "layout_color_cache_boundary"]
  end
  def layout_stage_observation
    record = body_stage_observation
    record[:layout_prefix] = prefix_snapshot
    record[:layout_partial_prefix] = @incomplete_capture
    record[:layout_executed] = true
    record[:layout_completed] = false
    raise "layout did not execute actual header" unless record[:layout_prefix].start_with?("<!DOCTYPE html>\n<html") && record[:layout_prefix].include?('<meta name="discourse_current_homepage"')
    raise "layout head omitted acquired icons" unless record[:layout_prefix].include?('rel="icon"') && record[:layout_prefix].include?('rel="apple-touch-icon"')
    raise "layout head omitted canonical/color metadata" unless record[:layout_prefix].include?('rel="canonical"') && record[:layout_prefix].include?('name="theme-color"')
    record
  end
end
class ListBodyContext
  include ListLayoutViewProtocol
  include NativeApplicationLayout
  def observation; layout_stage_observation; end
end
