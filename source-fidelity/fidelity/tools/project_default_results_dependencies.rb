# frozen_string_literal: true
# Only the real dependencies of supported default_results execution.
require "prism"
require "json"
require "digest"
root, output = ARGV
map_path = File.join(output, "projection-map.json")
map = JSON.parse(File.read(map_path))
specs = {
  "app/models/topic.rb" => {owner: "Topic", associations: %w[topic_tags tags]},
  "app/models/tag.rb" => {owner: "Tag", associations: %w[topic_tags topics target_tag]},
  "app/models/topic_tag.rb" => {owner: "TopicTag", associations: %w[topic tag]},
  "lib/topic_query.rb" => {owner: "TopicQuery", methods: %i[apply_custom_filters]},
  "lib/discourse_plugin_registry.rb" => {owner: "DiscoursePluginRegistry", methods: %i[apply_modifier]},
}
specs.each do |path, spec|
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == spec[:owner] }
  destination = "app/models/" + File.basename(path)
  prior = map.find { |entry| entry["generated"] == destination }
  projection = prior ? File.binread(File.join(output, destination)) : source.gsub(/[^\n]/, " ")
  spans = prior ? prior["selected_spans"] : []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
  end
  unless prior
    last = source.index("\n", owner.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, owner.location.start_offset, last - owner.location.start_offset), "real_source_dependency_owner")
    copy.call(owner.end_keyword_loc, "real_source_dependency_end")
  end
  owner.body.body.each do |node|
    if node.is_a?(Prism::DefNode) && spec.fetch(:methods, []).include?(node.name)
      copy.call(node.location, "whole_source_default_results_dependency:#{node.name}")
    elsif node.is_a?(Prism::CallNode) && %i[has_many belongs_to].include?(node.name) && spec.fetch(:associations, []).include?(node.arguments.arguments.first.unescaped)
      copy.call(node.location, "actual_source_association:#{node.arguments.arguments.first.unescaped}")
    end
  end
  raise "invalid default_results dependency projection" unless Prism.parse(projection).success?
  File.binwrite(File.join(output, destination), projection)
  map.reject! { |entry| entry["generated"] == destination }
  map << {source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "Supported anonymous default_results dependency only; omitted model lifecycle/write/list APIs NOT admitted"}
end
File.write(map_path, JSON.pretty_generate(map) + "\n")
