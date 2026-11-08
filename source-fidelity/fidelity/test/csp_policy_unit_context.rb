# frozen_string_literal: true
require "logger"
require "json"
module PortableCspUnitProfile
  # The actual Discourse fast_blank override, not Unicode-only blank?.
  def self.blank?(value)
    return true if value.nil?
    raise ArgumentError, "unsupported CSP presence value" unless value.is_a?(String)
    value.match?(/\A[\x00\x09-\x0d\x20]*\z/)
  end
  def self.presence(value)
    blank?(value) ? nil : value
  end
  def self.validate_build!(base_url, report_only)
    raise ArgumentError, "unsupported CSP base URL type profile" unless base_url.is_a?(String)
    raise ArgumentError, "unsupported CSP report mode profile" unless report_only == true || report_only == false
    nil
  end
  def self.validate_extension!(extension)
    raise ArgumentError, "unsupported non-Hash CSP extension profile" unless extension.is_a?(Hash)
    extension.each do |directive, sources|
      unless directive.is_a?(String) || directive.is_a?(Symbol)
        raise ArgumentError, "unsupported CSP directive key profile"
      end
      name = directive.to_s.gsub("-", "_").to_sym
      known = ContentSecurityPolicy::Builder::EXTENDABLE_DIRECTIVES + ContentSecurityPolicy::Builder::TO_BE_EXTENDABLE
      raise ArgumentError, "unsupported unknown CSP directive profile" unless known.include?(name)
      if sources.is_a?(Array)
        raise ArgumentError, "unsupported CSP source type profile" unless sources.all? { |source| source.is_a?(String) }
      elsif !sources.nil? && !sources.is_a?(String)
        raise ArgumentError, "unsupported CSP source type profile"
      end
    end
    nil
  end
end
class UnitCspSettings
  attr_reader :force_https, :content_security_policy_report_uri,
    :content_security_policy_frame_ancestors, :embed_any_origin, :script_reads
  def initialize(force_https, report_uri, restrict_embed, embed_any, script_src)
    [force_https, restrict_embed, embed_any].each do |value|
      raise ArgumentError, "unsupported non-boolean CSP setting profile" unless value == true || value == false
    end
    raise ArgumentError, "unsupported CSP report URI type profile" unless report_uri.nil? || report_uri.is_a?(String)
    raise ArgumentError, "unsupported CSP script source setting profile" unless script_src.is_a?(String)
    @force_https = force_https
    @content_security_policy_report_uri = report_uri
    @content_security_policy_frame_ancestors = restrict_embed
    @embed_any_origin = embed_any
    @script_src = script_src
    @script_reads = 0
  end
  def content_security_policy_script_src
    @script_reads += 1
    @script_src
  end
end
# Explicit UNIT EmbeddableHost fixture, not a SQL substitute or captured rows.
class UnitCspHostStore
  attr_reader :reads
  def initialize(hosts)
    raise ArgumentError, "unsupported UNIT host fixture type profile" unless hosts.is_a?(Array) && hosts.all? { |host| host.is_a?(String) }
    @hosts = hosts
    @reads = 0
  end
  def pluck(column)
    raise ArgumentError, "unsupported unit host fixture column" unless column == :host
    @reads += 1
    @hosts.dup
  end
end
class UnitCspExtensions
  attr_reader :calls, :themes, :plugins
  def initialize(themes, plugins, settings)
    @themes = themes
    @plugins = plugins
    @settings = settings
    @calls = []
    (themes + plugins).each { |extension| PortableCspUnitProfile.validate_extension!(extension) }
  end
  def theme_extensions(theme_id)
    @calls << "theme:#{theme_id}"
    @themes
  end
  def plugin_extensions
    @calls << "plugin"
    @plugins
  end
  def site_setting_extension
    {script_src: @settings.content_security_policy_script_src.split("|")}
  end
end
class UnitCspContext
  attr_reader :settings, :assets, :host_store, :extensions, :logger, :base_path
  def initialize(settings, assets, hosts, themes, plugins, log_path)
    @settings = settings
    [assets.relative_url_root, assets.cdn_url, assets.s3_cdn_url, assets.s3_asset_cdn_url].each do |value|
      raise ArgumentError, "unsupported CSP asset setting type profile" unless value.nil? || value.is_a?(String)
    end
    raise ArgumentError, "unsupported CSP asset mode profile" unless assets.use_s3? == true || assets.use_s3? == false
    @assets = assets
    @base_path = assets.relative_url_root || ""
    @host_store = UnitCspHostStore.new(hosts)
    @extensions = UnitCspExtensions.new(themes, plugins, settings)
    # Caller creates a private owned build fixture directory. Real Logger/IO
    # effects execute; a deterministic formatter changes presentation only.
    @log_path = log_path
    @log_file = File.open(log_path, "w", 0o600)
    @logger = Logger.new(@log_file)
    @logger.formatter = lambda { |severity, _time, _progname, message| "#{severity}: #{message}\n" }
  end
  def warnings
    @log_file.flush
    File.read(@log_path)
  end
  def close
    @logger.close
    nil
  end
end
