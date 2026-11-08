# frozen_string_literal: true
require_relative "list_color_source"
module ListLayoutColors
  def self.lookup(name, scheme_id)
    raise ArgumentError, "unsupported layout color name" unless name == "header_background"
    selected = ColorScheme.where(remote_copy: false).find_by(id: scheme_id) unless scheme_id.nil?
    if selected.nil?
      theme = Theme.where(id: SiteSetting.default_theme_id).first
      selected = ColorScheme.where(remote_copy: false).find_by(id: theme.color_scheme_id) unless theme.nil? || theme.color_scheme_id.nil?
    end
    value = if selected.nil?
      NativeListColorSource.base_colors[name]
    else
      row = selected.colors.find { |color| color.name == name }
      row.nil? ? nil : row.hex
    end
    raise TypeError, "source layout color missing" unless value.is_a?(String)
    value
  end
  def self.hex_for_name(name, scheme_id)
    key = scheme_id ? "#{name}_#{scheme_id}" : name
    key = "unadmitted_color" if ENV.fetch("FIDELITY_LAYOUT_FAULT", "") == "wrong-color-key"
    cache = CategoryCacheBootstrap.layout_color_cache
    raise "unbound native layout color cache" unless cache.is_a?(CategoryCacheApplication::DistributedCache)
    cache.defer_get_set(key) { lookup(name, scheme_id) }
  end
end
module ListLayoutColorProtocol
  def scheme_id
    raise ArgumentError, "unsupported layout user/cookie palette" unless current_user.nil? && request.env["HTTP_COOKIE"].nil?
    id = theme_id
    ActiveSupport.blank?(id) ? nil : Theme.where(id: id).pick(:color_scheme_id)
  end
  def dark_scheme_id
    raise ArgumentError, "unsupported layout user/cookie palette" unless current_user.nil? && request.env["HTTP_COOKIE"].nil?
    id = theme_id
    theme = Theme.where(id: ActiveSupport.blank?(id) ? SiteSetting.default_theme_id : id).first
    dark_id = theme.nil? ? nil : theme.dark_color_scheme_id
    return dark_id unless ActiveSupport.blank?(dark_id)
    limits = ActiveSupport.present?(id) && ThemeModifierSet.exists?(theme_id: id, only_theme_color_schemes: true)
    return theme.nil? ? nil : theme.color_scheme_id if limits
    -1
  end
  def dark_color_scheme?
    id = scheme_id
    return false if ActiveSupport.blank?(id)
    scheme = ColorScheme.where(remote_copy: false).find_by(id: id)
    scheme.nil? ? false : scheme.is_dark?
  end
  def forced_light_mode?
    return false if dark_color_scheme?
    raise ArgumentError, "unsupported forced layout palette" unless request.env["HTTP_COOKIE"].nil? && current_user.nil?
    false
  end
  def forced_dark_mode?
    return false if dark_scheme_id == -1
    raise ArgumentError, "unsupported forced layout palette" unless request.env["HTTP_COOKIE"].nil? && current_user.nil?
    false
  end
  def light_elements_media_query
    forced_light_mode? ? "all" : (forced_dark_mode? ? "none" : "(prefers-color-scheme: light)")
  end
  def dark_elements_media_query
    forced_light_mode? ? "none" : (forced_dark_mode? ? "all" : "(prefers-color-scheme: dark)")
  end
  def discourse_theme_color_meta_tags
    @events << "layout_color_cache_acquisition"
    result = if dark_scheme_id != -1
      light_media = light_elements_media_query
      light = ListLayoutColors.hex_for_name("header_background", scheme_id)
      dark_media = dark_elements_media_query
      dark = ListLayoutColors.hex_for_name("header_background", dark_scheme_id)
      "<meta name=\"theme-color\" media=\"#{light_media}\" content=\"##{light}\">\n<meta name=\"theme-color\" media=\"#{dark_media}\" content=\"##{dark}\">\n"
    else
      light = ListLayoutColors.hex_for_name("header_background", scheme_id)
      "<meta name=\"theme-color\" media=\"all\" content=\"##{light}\">\n"
    end
    return ActionView::HtmlFragment.new("") if ENV.fetch("FIDELITY_LAYOUT_FAULT", "") == "drop-color-tags"
    ActionView::HtmlFragment.new(result)
  end
  def discourse_color_scheme_meta_tag
    scheme = dark_scheme_id == -1 ? (dark_color_scheme? ? "dark" : "light") : "light dark"
    ActionView::HtmlFragment.new("<meta name=\"color-scheme\" content=\"#{scheme}\">\n")
  end
  def canonical_link_tag
    url = @controller.instance_variable_get(:@canonical_url)
    unless url
      url = Discourse.base_url_no_prefix + request.path
      pairs = []
      @controller.params.each { |key, value| pairs << "#{key}=#{value}" if key == "page" }
      url += "?" + pairs.join("&") unless pairs.empty?
      # Preserve the genuine localization predicate/crawler decision; locale
      # parameters are not admitted by this stage's explicit ingress profile.
      if SiteSetting.content_localization_enabled && SiteSetting.content_localization_crawler_param && SiteSetting.set_locale_from_param && controller.use_crawler_layout?
        raise ArgumentError, "unsupported localized canonical URL" if @controller.params.key?("tl")
      end
    end
    tag("link", {rel: "canonical", href: url})
  end
  def render_sitelinks_search_tag
    return nil unless guardian.can_search?
    raise ArgumentError, "unsupported homepage search metadata" if request.path == "/" || request.path == Discourse.base_path
    nil
  end
  def discourse_pageview_tracking_meta_tags
    return "" if Rails.env.development? && ActiveSupport.blank?(ENV["TRACK_REQUESTS"])
    raise ArgumentError, "unsupported active pageview tracking metadata"
  end
  def discourse_csrf_tags
    raise ArgumentError, "unsupported authenticated layout CSRF" unless current_user.nil?
    nil
  end
  def shared_session_key
    value = SiteSetting.long_polling_base_url
    raise ArgumentError, "unsupported authenticated shared layout session" if value != "/" && current_user
    nil
  end
  def allow_plugins?; !request.env[ApplicationController::NO_PLUGINS]; end
  def allow_third_party_plugins?; allow_plugins? && !request.env[ApplicationController::NO_UNOFFICIAL_PLUGINS]; end
  def staff?; current_user && current_user.staff?; end
  def expected_body_events
    ["template_lookup", "layout_lookup", "view_flow_receiver", "body_template", "view_flow_set", "layout_render", "layout_head_partial", "layout_color_cache_acquisition", "layout_head_returned", "layout_importmap_boundary"]
  end
end
class ListBodyContext
  include ListLayoutColorProtocol
end
