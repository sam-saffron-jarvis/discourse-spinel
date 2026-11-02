# frozen_string_literal: true
# Generate a source-only client settings contract from the pinned Discourse tree.
# Run from minimal/: ruby reference/generate-client-settings.rb
require "yaml"
require "json"
require "digest"
require "shellwords"

root = File.expand_path("../../discourse", __dir__)
source = File.join(root, "config/site_settings.yml")
expected_revision = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
actual_revision = `git -C #{Shellwords.escape(root)} rev-parse HEAD`.strip
abort "unexpected Discourse revision #{actual_revision}" unless actual_revision == expected_revision
settings = YAML.safe_load_file(source, aliases: true)
client = settings.values.flat_map(&:to_a).filter_map do |name, opts|
  next unless opts.is_a?(Hash) && opts["client"] == true
  next if opts["themeable"] == true || opts["secret"] == true
  explicit_type = opts["type"]
  source_type = if %w[upload uploaded_image_list category_list tag_list group_list list].include?(explicit_type)
    explicit_type
  elsif opts["default"].is_a?(TrueClass) || opts["default"].is_a?(FalseClass)
    "boolean"
  elsif opts["default"].is_a?(Integer)
    "integer"
  elsif opts["default"].is_a?(Float)
    "float"
  else
    explicit_type || "string"
  end
  {
    "name" => name,
    "default" => opts["default"],
    "type" => source_type,
    "upcoming_change" => opts["upcoming_change"],
    "upcoming_change_default_override" => opts["upcoming_change_default_override"],
    "source_client_flag" => true,
  }
end
# Ticket015: only source-client settings needed by the extracted anonymous
# counter/menu. This is not the complete plugin registry. Never include the
# server-only excluded-from-like setting in browser preloads.
plugin_source = File.join(root, "plugins/discourse-reactions/config/settings.yml")
plugin_names = %w[
  discourse_reactions_enabled discourse_reactions_like_icon
  discourse_reactions_reaction_for_like discourse_reactions_enabled_reactions
  discourse_reactions_desaturated_reaction_panel
]
plugin_settings = YAML.safe_load_file(plugin_source).fetch("discourse_reactions")
plugin_names.each do |name|
  opts = plugin_settings.fetch(name)
  abort "unsafe reactions client setting #{name}" unless opts["client"] == true && !opts["secret"] && !opts["themeable"]
  default = opts.fetch("default")
  type = default == true || default == false ? "boolean" : "string"
  client << { "name" => name, "default" => default, "type" => type,
              "upcoming_change" => nil, "upcoming_change_default_override" => nil,
              "source_client_flag" => true }
end
client << { "name" => "default_locale", "default" => "en", "type" => "string", "source_client_flag" => "SiteSettingExtension.client_settings default" }
details_source = File.join(root, "plugins/discourse-details/config/settings.yml")
details_plugin_settings = YAML.safe_load_file(details_source).fetch("plugins")
details_opts = details_plugin_settings.fetch("details_enabled")
abort "unsafe details client setting details_enabled" unless details_opts["client"] == true && !details_opts["secret"] && !details_opts["themeable"]
abort "details_enabled source default must be boolean" unless [true, false].include?(details_opts.fetch("default"))
client << { "name" => "details_enabled", "default" => details_opts.fetch("default"), "type" => "boolean",
            "upcoming_change" => nil, "upcoming_change_default_override" => nil,
            "source_client_flag" => true }
client.sort_by! { |row| row.fetch("name") }
promotion = settings.values.flat_map(&:to_a).find { |name, _opts| name == "promote_upcoming_changes_on_status" }&.last
output = {
  "source_revision" => expected_revision,
  "source_path" => "config/site_settings.yml",
  "source_sha256" => Digest::SHA256.file(source).hexdigest,
  "promote_upcoming_changes_on_status_default" => promotion&.fetch("default"),
  "generation" => "YAML client:true core settings plus five explicitly selected reactions counter/menu settings and discourse-details details_enabled; static defaults/types, never runtime overrides",
  "plugin_source_path" => "plugins/discourse-reactions/config/settings.yml",
  "plugin_source_sha256" => Digest::SHA256.file(plugin_source).hexdigest,
  "plugin_settings" => plugin_names,
  "details_plugin_source_path" => "plugins/discourse-details/config/settings.yml",
  "details_plugin_source_sha256" => Digest::SHA256.file(details_source).hexdigest,
  "details_plugin_settings" => ["details_enabled"],
  "settings" => client,
}
path = File.join(__dir__, "client-settings-contract.json")
serialized = JSON.pretty_generate(output) + "\n"
if ARGV == ["--check"]
  abort "source-derived client catalog is stale" unless File.read(path) == serialized
  puts "verified #{client.length} source-derived client settings"
else
  abort "usage: generate-client-settings.rb [--check]" unless ARGV.empty?
  File.write(path, serialized)
  puts "generated #{client.length} client:true source settings"
end
