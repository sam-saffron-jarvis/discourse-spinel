# frozen_string_literal: true
# Add the actual core result-filter registry, not a replacement empty getter.
require "prism"
require "json"
require "digest"
root, output = ARGV
source = File.binread(File.join(root, "lib/topic_query.rb"))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
selected = owner.body.body.grep(Prism::CallNode).select do |node|
  (node.name == :cattr_accessor && node.arguments.arguments.first.slice == ":results_filter_callbacks") ||
    (node.name == :results_filter_callbacks= && node.receiver&.slice == "self")
end
raise "core result-filter source declarations changed" unless selected.length == 2
path = File.join(output, "app/models/topic_query.rb")
projection = File.binread(path)
map_path = File.join(output, "projection-map.json")
map = JSON.parse(File.read(map_path))
entry = map.find { |item| item["generated"] == "app/models/topic_query.rb" }
selected.each do |node|
  projection[node.location.start_offset, node.location.length] = source[node.location.start_offset, node.location.length]
  entry["selected_spans"] << {role: "actual_core_result_filter_registry", start_byte: node.location.start_offset,
    end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
end
raise "invalid core result-filter projection" unless Prism.parse(projection).success?
File.binwrite(path, projection)
entry["generated_sha256"] = Digest::SHA256.hexdigest(projection)
File.write(map_path, JSON.pretty_generate(map) + "\n")
