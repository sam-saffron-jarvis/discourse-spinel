# frozen_string_literal: true
# TEST-only files/env for the production configuration component. No DB effects.
require "json"
require_relative "../compat/discourse/lib/site_settings/portable_global_configuration"
root = ENV.fetch("PORTABLE_CONFIGURATION_TEST_DIR")
defaults_path = root + "/defaults.conf"
config_path = root + "/discourse.conf"
keys = %w[cfg_false cfg_int cfg_blank cfg_quote]
previous = {}
keys.each { |key| previous[key] = ENV["DISCOURSE_" + key.upcase] }
begin
  keys.each { |key| ENV.delete("DISCOURSE_" + key.upcase) }
  File.write(defaults_path, "cfg_false = false\ncfg_int = 9\ncfg_blank =\ncfg_quote = 'hello # kept'\n")
  definitions = keys.map { |name| SiteSettings::PortableDefinition.new(name, "", 1, "{}") }
  config = SiteSettings::PortableGlobalConfiguration.new(definitions, defaults_path, config_path)
  missing = config.overrides("unit-site")
  # BaseProvider#resolve treats a false fallback as absent, but the STRING
  # "false" from a present environment/configuration value coerces to false.
  raise "source fallback/presence semantics changed" unless missing == {
    "cfg_false" => nil, "cfg_int" => 9, "cfg_blank" => nil, "cfg_quote" => "hello # kept"}
  ENV["DISCOURSE_CFG_FALSE"] = "false"
  ENV["DISCOURSE_CFG_INT"] = "0"
  env = config.overrides("unit-site")
  raise "live environment coercions changed" unless env["cfg_false"] == false && env["cfg_int"] == 0
  File.write(config_path, "")
  empty = config.overrides("unit-site")
  raise "file provider precedence changed" unless empty["cfg_false"].nil? && empty["cfg_int"] == 9
  File.write(config_path, "cfg_false = true\ncfg_int = -7\ncfg_blank = 'present'\n")
  file = config.overrides("unit-site")
  raise "file refresh/coercion changed" unless file["cfg_false"] == true && file["cfg_int"] == -7 && file["cfg_blank"] == "present"
  File.write(config_path, "cfg_int = <%= unimplemented_configuration_effect %>\n")
  begin
    config.overrides("unit-site")
    raise "unproved ERB silently ignored"
  rescue SiteSettings::PortableUnsupported => error
    raise "wrong ERB refusal" unless error.message.include?("ERB")
  end
  puts JSON.generate({scope: "shared configuration UNIT contract ONLY", defaults: missing, environment: env,
                      empty_file: empty, changed_file: file, erb_admitted: false})
ensure
  keys.each do |key|
    value = previous[key]
    value ? ENV["DISCOURSE_" + key.upcase] = value : ENV.delete("DISCOURSE_" + key.upcase)
  end
  File.delete(config_path) if File.exist?(config_path)
  File.delete(defaults_path) if File.exist?(defaults_path)
end
