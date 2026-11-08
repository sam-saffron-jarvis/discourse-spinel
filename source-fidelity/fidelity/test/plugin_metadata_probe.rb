# frozen_string_literal: true
# Original metadata parser/construction prefix ONLY. Read each actual original
# script as data; NEVER activate/evaluate it or substitute stored metadata.
%w[discourse-assign discourse-events discourse-solved].each do |source_plugin|
  path = File.join(ENV.fetch("FIDELITY_PLUGIN_SOURCE_ROOT"), "plugins", source_plugin, "plugin.rb")
  plugin = Plugin::Instance.parse_from_source(path)
  metadata = plugin.metadata
  puts "FIDELITY " + JSON.generate({
    kind: "plugin_metadata",
    source_plugin: source_plugin,
    name: metadata.name,
    about: metadata.about,
    version: metadata.version,
    authors: metadata.authors,
    contact_emails: metadata.contact_emails,
    url: metadata.url,
    required_version: metadata.required_version,
    meta_topic_id: metadata.meta_topic_id,
    label: metadata.label,
    official: metadata.official?,
  })
end
