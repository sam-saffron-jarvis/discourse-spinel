# frozen_string_literal: true
# UNIT fixtures ONLY. Exercises the actual production scalar accessor module;
# this host is not SiteSetting, a fake Guardian or a production settings input.
require "json"
require_relative "../compat/discourse/lib/site_settings/portable_core_definitions"
require_relative "../compat/discourse/lib/site_settings/portable_scalar_readers"
require_relative "../compat/discourse/lib/site_settings/portable_settings_context"
require_relative "generated/portable_group_ids_fixture"

class PortableScalarFixtureProvider
  def initialize
    @rows = {}
  end
  def replace(site, rows)
    @rows[site] = rows
  end
  def all(site)
    @rows[site] || []
  end
  def global_overrides(site)
    {}
  end
end

class PortableScalarReaderUnitHost
  include SiteSettings::PortableScalarReaders
  include SiteSettings::PortableSettingsContext
  attr_accessor :granular_anonymous_and_logged_in_groups_permissions

  def initialize(provider, site)
    configure_portable_settings(provider, site)
    # Explicit controlled UNIT input to the map's read-time branch, NOT an
    # implementation of UpcomingChanges or a claimed native security setting.
    @granular_anonymous_and_logged_in_groups_permissions = false
  end
end

provider = PortableScalarFixtureProvider.new
a = PortableScalarReaderUnitHost.new(provider, "scalar-unit-a")
b = PortableScalarReaderUnitHost.new(provider, "scalar-unit-b")
store = a.portable_store
raise "source default/type" unless a.title == "Discourse" && a.nested_replies_enabled == false
raise "scoped non-theme semantics" unless a.title({theme_id: 123}) == a.title
raise "predicate forwarding" unless a.title?({theme_id: 123}) == a.title
raise "unwrapped source enum" unless a.remove_muted_tags_from_latest == "always"
provider.replace("scalar-unit-a", [
  SiteSettings::PortableRow.new("title", "unit title", 1),
  SiteSettings::PortableRow.new("nested_replies_enabled", "true", 5),
  SiteSettings::PortableRow.new("remove_muted_tags_from_latest", "never", 7),
  SiteSettings::PortableRow.new("about_page_hidden_groups", "0|5|0|1", 20),
  SiteSettings::PortableRow.new("default_categories_muted", "1|2|2", 11),
])
store.refresh!("scalar-unit-a")
raise "provider/type/site isolation" unless a.title == "unit title" && a.nested_replies_enabled == true && b.title == "Discourse"
raise "enum DB precedence" unless a.remove_muted_tags_from_latest == "never"
a.granular_anonymous_and_logged_in_groups_permissions = false
old_map = a.about_page_hidden_groups_map
raise "disabled flag must preserve IDs/duplicates" unless old_map == [0, 5, 0, 1]
a.granular_anonymous_and_logged_in_groups_permissions = true
new_map = a.about_page_hidden_groups_map
raise "enabled flag must remap and deduplicate" unless new_map == [5, 1]
raise "read-time transform mutated storage" unless a.about_page_hidden_groups == "0|5|0|1"
a.granular_anonymous_and_logged_in_groups_permissions = false
raise "flag revert lost original IDs" unless a.about_page_hidden_groups_map == old_map
raise "category map changed" unless a.default_categories_muted_map == [1, 2, 2]
begin
  a.title = "not allowed"
  raise "write unexpectedly enabled"
rescue SiteSettings::PortableUnsupported => error
  raise "wrong write error" unless error.message.include?("writes")
end
begin
  store.get("duplicate_topic_titles", "scalar-unit-a")
  raise "wrapping enum incorrectly treated as raw"
rescue SiteSettings::PortableUnsupported => error
  raise "wrong wrapping-enum refusal" unless error.message.include?("special-getter")
end
begin
  a.configure_portable_settings(provider, "")
  raise "empty bootstrap site accepted"
rescue ArgumentError => error
  raise "wrong site error" unless error.message == "site must not be empty"
end
provider.replace("scalar-unit-invalid", [SiteSettings::PortableRow.new("title", "invalid", 99)])
begin
  a.configure_portable_settings(provider, "scalar-unit-invalid")
  raise "invalid replacement provider accepted"
rescue ArgumentError => error
  raise "wrong provider error" unless error.message == "type"
end
raise "failed bootstrap changed context" unless a.portable_store.equal?(store) && a.portable_site == "scalar-unit-a"
raise "failed bootstrap changed values" unless a.title == "unit title" && b.title == "Discourse"
puts JSON.generate({scope: "production scalar accessors UNIT-only controlled branch inputs",
  old_map: old_map, new_map: new_map, enum: a.remove_muted_tags_from_latest,
  scoped_getter: a.title({theme_id: 123}), native_upcoming_changes_accepted: false,
  native_full_site_setting_accepted: false, core_latest_accepted: false})
