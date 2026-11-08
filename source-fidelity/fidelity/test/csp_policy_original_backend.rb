# frozen_string_literal: true
# Explicit UNIT globals consumed by unmodified original Default/Builder methods.
# No Rails boot, Site settings/preloads, theme baking or DB-backed hosts.
require "action_dispatch"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/starts_ends_with"
require "active_support/core_ext/string/filters"
require "fast_blank"
require "uri"
# Verify the reference actually resolves the gem whose package/member was
# independently checked by the generator, not an accidental framework shim.
serializer_file = File.join(Gem.loaded_specs.fetch("actionpack").full_gem_path, "lib/action_dispatch/http/content_security_policy.rb")
raise "unsupported ActionDispatch CSP reference source" unless Gem.loaded_specs.fetch("actionpack").version.to_s == "8.1.4" && ActionDispatch::ContentSecurityPolicy.instance_method(:build).source_location.first == serializer_file
class SiteSetting
  class << self
    attr_accessor :unit_csp_settings
    def force_https; unit_csp_settings.force_https; end
    def content_security_policy_report_uri; unit_csp_settings.content_security_policy_report_uri; end
    def content_security_policy_frame_ancestors; unit_csp_settings.content_security_policy_frame_ancestors; end
    def embed_any_origin; unit_csp_settings.embed_any_origin; end
    def content_security_policy_script_src; unit_csp_settings.content_security_policy_script_src; end
  end
end
module GlobalSetting
  class << self
    attr_accessor :unit_settings
    def use_s3?; unit_settings.use_s3?; end
    def s3_cdn_url; unit_settings.s3_cdn_url; end
    def s3_asset_cdn_url; unit_settings.s3_asset_cdn_url; end
    def cdn_url; unit_settings.cdn_url; end
  end
end
module Discourse
  def self.base_path
    GlobalSetting.unit_settings.relative_url_root || ""
  end
end
class EmbeddableHost
  class << self
    attr_accessor :unit_store
    def pluck(column); unit_store.pluck(column); end
  end
end
module Rails
  class << self
    attr_accessor :unit_csp_logger
    def logger; unit_csp_logger; end
  end
end
class ContentSecurityPolicy
  module Extension
    extend self
    class << self
      attr_accessor :unit_provider
    end
    def theme_extensions(theme_id); unit_provider.theme_extensions(theme_id); end
    def plugin_extensions; unit_provider.plugin_extensions; end
  end
end

def unit_build_csp(context, base_url, report_only)
  PortableCspUnitProfile.validate_build!(base_url, report_only)
  # Validate the UNIT profile before original construction. Known source-defined
  # no-op directives remain source no-ops; unknown types aren't silently dropped.
  (context.extensions.themes + context.extensions.plugins).each { |extension| PortableCspUnitProfile.validate_extension!(extension) }
  SiteSetting.unit_csp_settings = context.settings
  GlobalSetting.unit_settings = context.assets
  EmbeddableHost.unit_store = context.host_store
  Rails.unit_csp_logger = context.logger
  ContentSecurityPolicy::Extension.unit_provider = context.extensions
  ContentSecurityPolicy.new.build("unit-theme", base_url: base_url, report_only: report_only)
end

def unit_default_directives(context, report_only)
  ContentSecurityPolicy::Default.new(report_only: report_only).directives
end
