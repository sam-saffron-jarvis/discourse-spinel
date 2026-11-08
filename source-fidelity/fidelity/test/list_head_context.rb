# frozen_string_literal: true
require_relative "list_head_source"
require_relative "emitted/runtime/action_view/view_helpers"
module SiteSettings
  class PortableReadStore
    # Source-specific read contract, NOT generic scalar admission or a forced
    # setting. Preserve the conservative generated special-getter declarations.
    def assert_html_local_upload_profile!(site)
      definition = @definitions["enable_s3_uploads"]
      raise PortableUnsupported, "unsupported HTML S3 declaration" unless definition && definition.data_type == 5 && !definition.themeable? && definition.options["portable_source_override"] == true && !definition.options.key?("upcoming_change") && !definition.options.key?("depends_on")
      refresh!(site) unless @mutex.synchronize { @values.key?(site) }
      value = @mutex.synchronize { @values[site]["enable_s3_uploads"] }
      raise PortableUnsupported, "unsupported body image S3 profile" unless value == false
      nil
    end
  end
end
module ListHeadImages
  class << self
    attr_accessor :configuration
  end
  def self.configure(configuration)
    self.configuration = configuration
    SiteSetting.portable_store.assert_html_local_upload_profile!(SiteSetting.portable_site)
    raise ArgumentError, "unsupported body image S3 profile" if ![nil, ""].include?(configuration.value("s3_bucket")) || ![nil, ""].include?(configuration.value("s3_cdn_url"))
    cdn = SiteSetting.portable_rendering_asset_host
    raise ArgumentError, "unsupported body image configured CDN" unless cdn.nil? || cdn == ""
  end
  def self.upload(name)
    raise ArgumentError, "unsupported body upload setting" unless %w[x_summary_large_image opengraph_image large_icon logo_small logo favicon apple_touch_icon].include?(name)
    value = SiteSetting.portable_store.get_upload_id(name, SiteSetting.portable_site)
    Upload.find_by(id: value) if value != Upload::SEEDED_ID_THRESHOLD
  end
  def self.resolve_original(settings, fallback)
    settings.each do |name|
      value = upload(name)
      return value unless value.nil?
    end
    fallback ? Upload.find_by(id: ListHeadSource::SKETCH_LOGO_ID) : nil
  end
  def self.full_cdn_url(url)
    # Actual GlobalPath/UrlHelper local-store branch, guarded at configure.
    return url if url.start_with?("http://", "https://")
    scheme = SiteSetting.force_https ? "https" : "http"
    return scheme + ":" + url if url.start_with?("//")
    raise ArgumentError, "unsupported relative body upload URL" unless url.start_with?("/")
    Discourse.base_url_no_prefix + url
  end
  def self.icon_url(name)
    info = ListHeadSource::ICON_INFO[name]
    raise ArgumentError, "unsupported list icon role" if info.nil?
    cache = CategoryCacheBootstrap.body_icon_cache
    raise ArgumentError, "unbound native icon cache" unless cache.is_a?(CategoryCacheApplication::DistributedCache)
    cache.defer_get_set(name + "_url") do
      icon = resolve_original(info[:settings], info[:fallback_to_sketch])
      result = nil
      if !icon.nil? && info[:height] && info[:width]
        result = OptimizedImage.find_by(upload_id: icon.id, height: info[:height], width: info[:width])
      end
      result = icon if result.nil? && !info[:resize_required]
      result.nil? ? "" : full_cdn_url(result.url)
    end
  end
end
module BodyHeadImageReaders
  def site_x_summary_large_image_url
    value = ListHeadImages.upload("x_summary_large_image")
    value.nil? ? "" : ListHeadImages.full_cdn_url(value.url)
  end
  def site_logo_url
    value = ListHeadImages.upload("logo")
    value.nil? ? "" : ListHeadImages.full_cdn_url(value.url)
  end
  def site_opengraph_image_url; ListHeadImages.icon_url("opengraph_image"); end
  def site_favicon_url; ListHeadImages.icon_url("favicon"); end
  def site_apple_touch_icon_url; ListHeadImages.icon_url("apple_touch_icon"); end
end
SiteSetting.extend(BodyHeadImageReaders)
module ListHeadViewProtocol
  def rss_url(options)
    raise ArgumentError, "unsupported RSS URL generation profile" unless options[:action] == "latest_feed" && options[:only_path] == false && (options.keys - [:action, :params, :only_path]).empty?
    values = options[:params] || {}
    pairs = []
    values.each do |key, value|
      raise TypeError, "unsupported RSS non-scalar query parameter" unless key.is_a?(String) && value.is_a?(String)
      pairs << ActionView::ViewHelpers.url_encode(key) + "=" + ActionView::ViewHelpers.url_encode(value)
    end
    query = pairs.sort.join("&")
    url = request.base_url + request.env["SCRIPT_NAME"].to_s + ListHeadSource::LATEST_FEED_PATH
    query.empty? ? url : url + "?" + query
  end
  def url_for(options); rss_url(options); end
  def auto_discovery_link_tag(type, url_options, title:)
    raise ArgumentError, "unsupported list RSS MIME profile" unless type == :rss
    return ActionView::HtmlFragment.new("") if ENV.fetch("FIDELITY_BODY_FAULT", "") == "drop-rss"
    href = url_options.is_a?(Hash) ? url_for(url_options.merge(only_path: false)) : url_options
    tag("link", {"rel" => "alternate", "type" => ListHeadSource::RSS_MIME, "title" => title, "href" => href})
  end
  def tag(name, options, open = false, escape = true)
    raise ArgumentError, "unsupported list metadata tag/trust profile" unless ["link", "meta"].include?(name.to_s) && !open && escape
    output = +"<#{name}"
    options.each do |key, value|
      raise ArgumentError, "unsupported list metadata attribute" unless %w[rel type title href property content name value].include?(key.to_s)
      unless value.nil?
        raise TypeError, "non-scalar list metadata attribute" unless value.is_a?(String) || value == true || value == false || value.is_a?(Integer)
        output << " #{key}=\"" << ERB::Util.html_escape(value.to_s) << "\""
      end
    end
    output << " />"
    ActionView::HtmlFragment.new(output)
  end
  def get_absolute_image_url(link)
    return Discourse.base_url.split(":", 2).first + ":" + link if link.start_with?("//")
    return Discourse.base_url + link if link.start_with?("/uploads/", "/images/", "/user_avatar/")
    relative = ListHeadImages.configuration.value("relative_url_root")
    relative && link.start_with?(relative) ? Discourse.base_url_no_prefix + link : link
  end
  def crawlable_meta_data(title:, description:)
    return "" if ENV.fetch("FIDELITY_BODY_FAULT", "") == "drop-metadata"
    url = Discourse.base_url_no_prefix + request.fullpath
    raise ArgumentError, "unsupported invalid-encoding metadata URL" unless url.valid_encoding?
    x_image = SiteSetting.site_x_summary_large_image_url
    image = SiteSetting.site_opengraph_image_url
    image = get_absolute_image_url(image) unless image.empty?
    x_image = get_absolute_image_url(x_image) unless x_image.empty?
    result = []
    result << tag(:meta, {property: "og:site_name", content: SiteSetting.title}).to_s
    result << tag(:meta, {property: "og:type", content: "website"}).to_s
    card_image = x_image.empty? ? image : x_image
    if card_image.end_with?(".svg")
      logo = SiteSetting.site_logo_url
      card_image = logo.end_with?(".svg") ? "" : logo
    end
    card = !x_image.empty? && !card_image.empty? ? "summary_large_image" : "summary"
    result << tag(:meta, {name: "twitter:card", content: card}).to_s
    result << tag(:meta, {name: "twitter:image", content: card_image}).to_s if !card_image.empty? && (!x_image.empty? || !image.empty?)
    result << tag(:meta, {property: "og:image", content: image}).to_s unless image.empty?
    {url: url, title: title, description: description}.each do |property, value|
      next if ActiveSupport.blank?(value)
      content = property == :url ? value : Emoji.gsub_emoji_to_unicode(value)
      content = DiscoursePluginRegistry.apply_modifier(:meta_data_content, content, property, {url: url, title: title, description: description, image: image, x_summary_large_image: x_image})
      result << tag(:meta, {property: "og:#{property}", content: content}, nil, true).to_s
      result << tag(:meta, {name: "twitter:#{property}", content: content}, nil, true).to_s
    end
    result.join("\n")
  end
end
class ListBodyContext
  include ListHeadViewProtocol
end
