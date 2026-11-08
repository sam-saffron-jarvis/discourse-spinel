# frozen_string_literal: true
# Genuine original Rails scalar value, with its real cache entry removed to
# exercise the original refresh/callback path before selected-expression tracing.
raise "no-plugin profile required" unless ENV["LOAD_PLUGINS"] == "0" && !GlobalSetting.load_plugins?
SiteSetting.current.delete(:suppress_secured_categories_from_admin)
value = SiteSetting.suppress_secured_categories_from_admin
puts "FIDELITY_PORTABLE_SECURITY_BOOT " + JSON.generate({
  value: value, ruby_class: value.class.name, site_source: "original Rails provider current_site",
  setting_source: SiteSetting.method(:suppress_secured_categories_from_admin).source_location,
})
load File.join(__dir__, "anonymous_security_oracle_consumer.rb")
