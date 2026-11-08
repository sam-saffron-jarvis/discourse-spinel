# frozen_string_literal: true
# Pure framework helpers, not ActionView/Rails application boot.
require "active_support/core_ext/string/starts_ends_with"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/object/to_query"
require "active_support/core_ext/enumerable"
require_relative "original_list_head_helpers"
class OriginalListTagCarrier
  include OriginalHeadTagHelper
end
module OriginalListIcons
  # Source belongs_to :upload is a foreign-key predicate in real ActiveRecord.
  # Bind that protocol explicitly; emitted generic Hash#where does not translate
  # association keys. Values come from the genuine Upload, never supplied rows.
  module OptimizedImage
    def self.find_by(upload:, height:, width:)
      ::OptimizedImage.find_by(upload_id: upload&.id, height: height, width: width)
    end
  end
  def self.acquire_cache
    @cache ||= CategoryCacheBootstrap.body_icon_cache
  end
end
module OriginalHeadImageReaders
  def site_opengraph_image_url
    OriginalListIcons.acquire_cache
    OriginalListIcons.opengraph_image_url
  end
  def site_favicon_url
    OriginalListIcons.acquire_cache
    OriginalListIcons.favicon_url
  end
  def site_apple_touch_icon_url
    OriginalListIcons.acquire_cache
    OriginalListIcons.apple_touch_icon_url
  end
end
SiteSetting.extend(OriginalHeadImageReaders)
class OriginalListBodyContext
  include ListHeadViewProtocol
  include OriginalListHeadHelpers
  def tag(*args, **options)
    # Delegate to the actual TagHelper without importing CaptureHelper over the
    # explicit real OutputBuffer/slot protocol used by this isolated view.
    OriginalListTagCarrier.new.tag(*args, **options)
  end
  def url_for(options)
    raise ArgumentError, "unsupported original RSS route profile" unless options[:action] == "latest_feed" && options[:only_path] == false && (options.keys - [:action, :params, :only_path]).empty?
    query = (options[:params] || {}).to_query
    url = request.base_url + request.env["SCRIPT_NAME"].to_s + ListHeadSource::LATEST_FEED_PATH
    query.empty? ? url : url + "?" + query
  end
end
