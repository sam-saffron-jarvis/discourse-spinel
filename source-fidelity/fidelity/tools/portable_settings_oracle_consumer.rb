# frozen_string_literal: true
# Original guarded no-plugin Rails FIRST; new shared read-store comparison ONLY.
# SiteSetting has NOT been replaced in this reference process.
load File.join(__dir__, "core_no_plugins_reference_consumer.rb")
require_relative "../test/portable_settings_records"
definitions = SiteSettings::PortableCoreDefinitions.build
configuration = SiteSettings::PortableGlobalConfiguration.new(
  definitions, Rails.root.join("config/discourse_defaults.conf").to_s,
  Rails.root.join("config/discourse.conf").to_s,
)
connection = ActiveRecord::Base.connection.raw_connection
site = connection.exec("SELECT current_database()").getvalue(0, 0)
provider = SiteSettings::PortablePgProvider.new({site => connection}, configuration)
store = SiteSettings::PortableReadStore.new(definitions, provider)
selected = PortableSettingsRecords.definitions_for_comparison(definitions)
original = selected.map do |definition|
  value = SiteSetting.public_send(definition.name)
  [definition.name, value.class.name, value]
end
candidate = PortableSettingsRecords.read(store, selected, site)
# Both source values and their Ruby classes participate; no loose true/1 match.
raise "portable read-store differs from original Rails" unless original == candidate
puts "FIDELITY_PORTABLE_SETTINGS " + JSON.generate({
  profile: "patched-core-no-plugins-shared-settings-read-store", scope: "live original Rails vs NEW shared store scalar reader ONLY; NOT patched Rails bootstrap or full SiteSetting",
  site_key_source: "active readonly PG current_database()", definitions: definitions.length,
  compared: candidate.length, records: candidate,
  excluded: definitions.reject { |definition| selected.include?(definition) }.map(&:name),
  full_site_setting_accepted: false, core_latest_accepted: false,
})
