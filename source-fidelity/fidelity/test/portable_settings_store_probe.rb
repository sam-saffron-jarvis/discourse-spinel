# frozen_string_literal: true
# Unit controls for the NEW production read-store, not production settings data,
# a fake SiteSetting, a Rails replacement, or /latest acceptance.
require "json"
require_relative "../compat/discourse/lib/site_settings/portable_core_definitions"
require_relative "../compat/discourse/lib/site_settings/portable_core_readers"
require_relative "../compat/discourse/lib/site_settings/portable_html_homepage_readers"

class PortableSettingsMemoryProvider
  def initialize
    @rows = {}
    @overrides = {}
  end
  def replace(site, rows)
    @rows[site] = rows
  end
  def shadow(site, overrides)
    @overrides[site] = overrides
  end
  def all(site)
    @rows[site] || []
  end
  def global_overrides(site)
    @overrides[site] || {}
  end
end

class PortableSettingsReaderControl
  include SiteSettings::PortableCoreReaders
  def initialize(store, site)
    @store = store
    @site = site
  end
  def portable_store
    @store
  end
  def portable_site
    @site
  end
end

source_definitions = SiteSettings::PortableCoreDefinitions.build
raise "source definitions missing" unless source_definitions.length == 1111
definitions = source_definitions + [
  SiteSettings::PortableDefinition.new("probe_false", false, 5, '{"client":true}'),
  SiteSettings::PortableDefinition.new("probe_zero", 0, 3, '{}'),
  SiteSettings::PortableDefinition.new("probe_empty", "", 1, '{}'),
  SiteSettings::PortableDefinition.new("probe_text", "hello", 1, '{"locale_default":{"fr":"bonjour"}}'),
  SiteSettings::PortableDefinition.new("probe_mandatory", "", 8, '{"mandatory_values":"keep"}'),
  SiteSettings::PortableDefinition.new("probe_secret", "not-a-real-secret", 1, '{"secret":true,"hidden":true}'),
]
provider = PortableSettingsMemoryProvider.new
store = SiteSettings::PortableReadStore.new(definitions, provider)
a = PortableSettingsReaderControl.new(store, "unit-a")
b = PortableSettingsReaderControl.new(store, "unit-b")
raise "false default lost" unless store.get("probe_false", "unit-a") == false
raise "zero default/type lost" unless store.get("probe_zero", "unit-a") == 0
raise "empty default lost" unless store.get("probe_empty", "unit-a") == ""
raise "real source accessor lost" unless a.title == "Discourse" && a.title? == "Discourse"
raise "YAML string mutability changed" if a.title.frozen?
raise "default locale predicate changed" unless a.default_locale? == true
raise "membership changed" unless store.has_setting?(:title) && store.has_setting?("title?") && !store.has_setting?(:unknown)
provider.replace("unit-a", [SiteSettings::PortableRow.new("title", "live-a", 1),
  SiteSettings::PortableRow.new("probe_false", "t", 5), SiteSettings::PortableRow.new("probe_zero", "17", 3),
  SiteSettings::PortableRow.new("default_locale", "fr", 1), SiteSettings::PortableRow.new("probe_mandatory", "other|keep", 8)])
provider.replace("unit-b", [SiteSettings::PortableRow.new("title", "live-b", 1)])
notifications = []
store.refresh!("unit-a") do |site, changed, removed|
  notifications << [site, changed.include?("title"), removed.length, store.get("title", site)]
end
store.refresh!("unit-b")
raise "live provider precedence" unless a.title == "live-a" && b.title == "live-b"
raise "typed override" unless store.get("probe_false", "unit-a") == true && store.get("probe_zero", "unit-a") == 17
raise "locale override" unless store.get("probe_text", "unit-a") == "bonjour" && store.get("probe_text", "unit-b") == "hello"
raise "mandatory merge" unless store.get("probe_mandatory", "unit-a") == "keep|other"
raise "refresh callback/publication order" unless notifications == [["unit-a", true, 0, "live-a"]]
raise "modified values" unless store.setting_modified_from_default?(:title, "unit-a")
provider.replace("unit-a", [SiteSettings::PortableRow.new("title", "changed-a", 1)])
raise "cache did not cache" unless a.title == "live-a"
store.invalidate!("unit-a")
raise "refresh/site isolation" unless a.title == "changed-a" && b.title == "live-b"
raise "removed override didn't return to default" unless store.get("probe_zero", "unit-a") == 0
provider.shadow("unit-a", {"title" => "config-a", "probe_false" => false, "probe_zero" => 0, "probe_empty" => ""})
store.refresh!("unit-a")
raise "live global precedence" unless a.title == "config-a" && b.title == "live-b"
raise "false global lost" unless store.get("probe_false", "unit-a") == false
raise "shadow visibility" unless store.hidden?("title", "unit-a") && !store.hidden?("title", "unit-b")
raise "secret visibility" unless store.hidden?("probe_secret", "unit-a")
# Unknown/invalid DB type must not publish half a refresh or cross-talk.
provider.replace("unit-a", [SiteSettings::PortableRow.new("title", "partial", 1), SiteSettings::PortableRow.new("probe_zero", "9", 99)])
begin
  store.refresh!("unit-a")
  raise "invalid wire type accepted"
rescue ArgumentError => error
  raise "wrong wire type error" unless error.message == "type"
end
raise "failed refresh published partial cache" unless a.title == "config-a" && b.title == "live-b"
begin
  store.get("not_a_setting", "unit-a")
  raise "unknown setting accepted"
rescue ArgumentError => error
  raise "unknown error changed" unless error.message == "No setting named 'not_a_setting' exists"
end
begin
  a.title = "forbidden-write"
  raise "unproved DB writes enabled"
rescue SiteSettings::PortableUnsupported => error
  raise "wrong write refusal" unless error.message.include?("writes")
end
begin
  a.personal_message_enabled_groups_map
  raise "unproved security map enabled"
rescue SiteSettings::PortableUnsupported => error
  raise "wrong security refusal" unless error.message.include?("security map")
end
# Owning UNIT controls for the getter actually used by the new HTML stage.
# These memory-provider values/status ranks NEVER feed an application request.
unit_statuses = {stable: 300, beta: 200, never: 9999, permanent: 500}
unit_top = source_definitions.find { |definition| definition.name == "top_menu" }
unit_old = unit_top.default_value
unit_new = unit_top.options.fetch("upcoming_change_default_override").fetch("new_default")
[
  [[], unit_new],
  [[SiteSettings::PortableRow.new("enable_unified_new", "f", 5)], unit_old],
  [[SiteSettings::PortableRow.new("enable_unified_new", "t", 5)], unit_new],
  [[SiteSettings::PortableRow.new("top_menu", unit_old, 8)], unit_old],
  [[SiteSettings::PortableRow.new("promote_upcoming_changes_on_status", "never", 7)], unit_old],
].each do |unit_rows, expected|
  provider.replace("unit-html", unit_rows)
  store.invalidate!("unit-html")
  raise "HTML top-menu unit precedence changed" unless store.get_top_menu_for_html("unit-html", unit_statuses) == expected
end
provider.replace("unit-html", [])
provider.shadow("unit-html", {"top_menu" => "unit-only|menu"})
store.invalidate!("unit-html")
raise "HTML global menu precedence changed" unless store.get_top_menu_for_html("unit-html", unit_statuses) == "unit-only|menu"
provider.shadow("unit-html", {})
[[SiteSettings::PortableRow.new("top_menu", "t", 5)],
 [SiteSettings::PortableRow.new("promote_upcoming_changes_on_status", "unit-unknown", 7)]].each do |unit_rows|
  provider.replace("unit-html", unit_rows)
  store.invalidate!("unit-html")
  begin
    store.get_top_menu_for_html("unit-html", unit_statuses)
    raise "unsupported HTML menu profile admitted"
  rescue SiteSettings::PortableUnsupported
  end
end
# Cover original wire distinctions independently of an effective data snapshot.
wire = [store.coerce("title", nil, 1), store.coerce("probe_zero", nil, 3),
  store.coerce("probe_false", "false", 5), store.coerce("probe_empty", nil, 8),
  store.coerce("title", "ignored", 6), store.coerce("title", "2.75", 4)]
raise "wire coercions changed" unless wire == ["", 0, false, nil, nil, 2.75]
puts JSON.generate({scope: "patched shared read-store UNIT contract ONLY", definitions: source_definitions.length,
                    notifications: notifications, wire: wire, full_site_setting_accepted: false, core_latest_accepted: false})
