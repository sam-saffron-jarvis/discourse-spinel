# frozen_string_literal: true
# Verify ownership in the fully booted real Rails process. Do NOT replace any
# class or re-activate plugins; the consumer only parses their source as data.
{
  Plugin::Instance.method(:parse_from_source) => ["lib/plugin/instance.rb", 109],
  Plugin::Instance.instance_method(:initialize) => ["lib/plugin/instance.rb", 115],
  Plugin::Metadata.method(:parse) => ["lib/plugin/metadata.rb", 32],
  Plugin::Metadata.instance_method(:parse_line) => ["lib/plugin/metadata.rb", 42],
}.each do |method, (path, line)|
  raise "original metadata producer changed; expand source closure" unless method.source_location == [File.expand_path(path), line]
end
raise "wrong original official-plugin resource" unless Digest::SHA256.file("config/official_plugins.json").hexdigest == Digest::SHA256.file(ENV.fetch("FIDELITY_OFFICIAL_PLUGIN_RESOURCE")).hexdigest
