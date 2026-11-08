# frozen_string_literal: true
require_relative "../compat/discourse/lib/site_settings/portable_read_store"
class UploadReadProviderUnit
  attr_accessor :rows
  def initialize
    @rows = {"a" => [], "b" => [SiteSettings::PortableRow.new("logo_small", "42", 18)]}
  end
  def all(site)
    @rows.fetch(site)
  end
  def global_overrides(site)
    {}
  end
end
provider = UploadReadProviderUnit.new
definitions = [SiteSettings::PortableDefinition.new("logo_small", -6, 18, '{"type":"upload"}'),
  SiteSettings::PortableDefinition.new("title", "source default", 1, '{}'),
  SiteSettings::PortableDefinition.new("theme_logo", 0, 18, '{"type":"upload","themeable":true}')]
store = SiteSettings::PortableReadStore.new(definitions, provider)
raise "source default ID" unless store.get_upload_id("logo_small", "a") == -6
raise "live per-site override" unless store.get_upload_id("logo_small", "b") == 42
provider.rows["b"] = [SiteSettings::PortableRow.new("logo_small", "0", 18)]
store.refresh!("b")
raise "live refresh" unless store.get_upload_id("logo_small", "b") == 0
raise "site bleed" unless store.get_upload_id("logo_small", "a") == -6
["title", "theme_logo"].each do |name|
  begin
    store.get_upload_id(name, "a")
    raise "invalid upload contract accepted"
  rescue SiteSettings::PortableUnsupported
  end
end
begin
  store.get("logo_small", "a")
  raise "scalar special-getter guard weakened"
rescue SiteSettings::PortableUnsupported
end
puts "UPLOAD_ID_UNIT real_defaults_live_overrides_refresh_site_isolation_and_refusals_ONLY"
