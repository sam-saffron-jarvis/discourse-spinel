# frozen_string_literal: true
# Supplied UNIT configuration only, not GlobalSetting/production state.
class UnitAssetSettings
  attr_reader :relative_url_root, :cdn_url, :s3_cdn_url, :s3_asset_cdn_url
  def initialize(relative_root, cdn, use_s3, s3_cdn, s3_asset_cdn)
    @relative_url_root = relative_root
    @cdn_url = cdn
    @use_s3 = use_s3
    @s3_cdn_url = s3_cdn
    @s3_asset_cdn_url = s3_asset_cdn
  end
  def use_s3?
    @use_s3
  end
  def asset_host
    cdn_url
  end
  def default_asset_host_protocol
    nil
  end
end
class UnitUrlRequest
  attr_reader :env
  def initialize(encoding)
    @env = {}
    @env["HTTP_ACCEPT_ENCODING"] = encoding if encoding
  end
end
class UnitUrlHelper
  include PortableAssetUrlMethods
  attr_reader :settings, :asset_paths, :request
  def initialize(settings, paths, encoding)
    @settings = settings
    @asset_paths = paths
    @request = UnitUrlRequest.new(encoding)
  end
end
