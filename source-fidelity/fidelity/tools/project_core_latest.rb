# frozen_string_literal: true
# PARTIAL latest-method closure, not full TopicQuery or page admission. Whole
# selected methods/constant/accessor declarations retain original bytes/spans.
require_relative "project_topic_query"

root = ARGV.fetch(0)
output = ARGV.fetch(1)
path = "lib/topic_query.rb"
source = File.binread(File.join(root, path))
parsed = Prism.parse(source)
raise "invalid query source" unless parsed.success?
owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "TopicQuery" }
raise "missing original query owner" unless owner
methods = owner.body.body.select { |node| node.is_a?(Prism::DefNode) }
# Start with actual latest entrypoints, not a trace's observed values/branches.
# Close conservatively over SAME-OWNER method names in every complete body,
# including unexecuted option branches. No settings/permission value is folded.
selected = methods.select do |node|
  %i[initialize list_latest latest_results default_results create_list].include?(node.name) && node.receiver.nil?
end
raise "missing latest entrypoint" unless selected.length == 5
loop do
  called_names = selected.flat_map { |node| nodes(node).grep(Prism::CallNode).map(&:name) }.uniq
  additions = methods.select { |node| called_names.include?(node.name) && !selected.include?(node) }
  break if additions.empty?
  selected.concat(additions)
end

projection = source.gsub(/[^\n]/, " ")
spans = []
copy = lambda do |location, role|
  projection[location.start_offset, location.length] = source[location.start_offset, location.length]
  spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
    start_line: location.start_line, end_line: location.end_line,
    text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
end
line_end = source.index("\n", owner.location.start_offset)
copy.call(Prism::Location.new(parsed.source, owner.location.start_offset, line_end - owner.location.start_offset), "owner")
copy.call(owner.end_keyword_loc, "owner_end")
selected.each { |node| copy.call(node.location, "whole_method:#{node.receiver ? 'self.' : ''}#{node.name}") }
owner.body.body.each do |node|
  if node.is_a?(Prism::ConstantWriteNode)
    copy.call(node.location, "source_constant:#{node.name}")
  elsif node.is_a?(Prism::CallNode) && %i[attr_accessor attr_reader cattr_accessor].include?(node.name)
    copy.call(node.location, "source_accessor:#{node.name}")
  elsif node.is_a?(Prism::CallNode) && %i[protected private public].include?(node.name) && node.arguments.nil?
    copy.call(node.location, "source_visibility:#{node.name}")
  elsif node.is_a?(Prism::CallNode) && node.name == :results_filter_callbacks=
    copy.call(node.location, "source_callback_registry_initialization")
  end
end
maps_path = File.join(output, "projection-map.json")
maps = JSON.parse(File.read(maps_path)).reject { |item| item["generated"] == "app/models/topic_query.rb" }
File.binwrite(File.join(output, "app/models/topic_query.rb"), projection)
maps << {source: path, generated: "app/models/topic_query.rb", source_sha256: Digest::SHA256.hexdigest(source),
  generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
  limitation: "PARTIAL whole-method latest closure; original methods/option branches unchanged, other list APIs/private-message module and dependent model closure NOT admitted"}
File.write(maps_path, JSON.pretty_generate(maps) + "\n")
File.write(File.join(output, "latest-method-closure.json"), JSON.pretty_generate({
  scope: "PARTIAL whole-method latest dependency measurement ONLY", method_count: selected.length,
  methods: selected.map { |node| {name: node.name, singleton: !node.receiver.nil?} },
  source_values_or_runtime_reachability_used: false, other_list_apis_admitted: false,
  complete_default_results_admitted: false, core_latest_accepted: false,
}) + "\n")
