# frozen_string_literal: true
# UNIT ONLY: real configuration/URI codec components; no app actors or DB.
require "addressable/uri"
require_relative "../compat/discourse/lib/portable_avatar_encoding"
require_relative "../compat/discourse/lib/site_settings/portable_global_configuration"

samples = [(0..127).map(&:chr).join, "héllo/東京 😀", "a%20b?x=1&y={size}", ""]
samples.each do |value|
  raise "URI byte encoding drift" unless PortableAvatarEncoding.component(value) == Addressable::URI.encode_component(value)
end
raise "nil component contract" unless PortableAvatarEncoding.component(nil).nil?
begin
  PortableAvatarEncoding.component(1)
  raise "unsupported non-String component accepted"
rescue TypeError
end

root = ENV.fetch("PORTABLE_SERIALIZER_TEST_DIR")
defaults = File.join(root, "defaults.conf")
configuration = File.join(root, "discourse.conf")
File.write(defaults, "hostname = source-global-default.example\n")
File.write(configuration, "hostname = configured-global.example\n")
config = SiteSettings::PortableGlobalConfiguration.new([], defaults, configuration)
keys = %w[RAILS_ENV DISCOURSE_HOSTNAME]
previous = keys.to_h { |key| [key, ENV[key]] }
begin
  ENV["RAILS_ENV"] = "development"
  ENV.delete("DISCOURSE_HOSTNAME")
  raise "global config getter changed" unless config.value("hostname") == "configured-global.example"
  raise "database routing incorrectly uses GlobalSetting.hostname" unless config.database_hostname == "localhost"
  ENV["DISCOURSE_HOSTNAME"] = "live-host.example"
  raise "database hostname froze an effective value" unless config.database_hostname == "live-host.example"
  ENV["DISCOURSE_HOSTNAME"] = ""
  raise "database.yml ENV truthiness changed" unless config.database_hostname == ""
  File.write(File.join(root, "multisite.yml"), "# UNIT ONLY\n")
  begin
    config.database_hostname
    raise "unimplemented multisite silently accepted"
  rescue SiteSettings::PortableUnsupported
  end
  File.delete(File.join(root, "multisite.yml"))
  ENV["RAILS_ENV"] = "production"
  begin
    config.database_hostname
    raise "unimplemented production routing silently accepted"
  rescue SiteSettings::PortableUnsupported
  end
ensure
  previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
end
puts "PASS source URI codec and live single-site configuration UNIT ONLY"
