# frozen_string_literal: true
# New-profile source-root expansion, separate from every historical projector.
# Whole methods/declarations only; no branch or setting/live-value pruning.
require "prism"
require "json"
require "digest"
def descendants(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| descendants(child, result) }
  result
end
root, output, candidate_root = ARGV
maps_path = File.join(output, "projection-map.json")
map = JSON.parse(File.read(maps_path))
candidate_path = File.join(output, "candidate-model-projections.json")
candidates = JSON.parse(File.read(candidate_path))
specs = {
  "app/models/topic.rb" => {scopes: %i[listable_topics visible secured], includes: %w[HasCustomFields Trashable],
    methods: %i[preload_custom_fields], associations: %w[category]},
  "app/models/category.rb" => {methods: %i[subcategory_ids]},
  # Only list_latest's source-owned helper API roots and their static closure.
  # TopicList#attributes is NOT such a root: original code calls undefined page,
  # and the actual TopicListSerializer reads more_topics_url directly. No claim
  # is made that the inherited serializable_hash/unused helper APIs are native.
  "app/models/topic_list.rb" => {methods: %i[initialize topics on_preload cancel_preload on_preload_user_ids preload preload_user_ids],
    declarations: %i[include attr_accessor attr_reader cattr_accessor preloaded_custom_fields=]},
}
specs.each do |path, spec|
  candidate = File.file?(File.join(candidate_root, path))
  source = File.binread(File.join(candidate ? candidate_root : root, path))
  parsed = Prism.parse(source)
  raise "invalid source #{path}" unless parsed.success?
  owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) }
  sha = Digest::SHA256.hexdigest(source)
  prior = (candidate ? candidates : map).find { |entry| entry["generated"] == path }
  reuse = prior && prior["source_sha256"] == sha && !spec[:methods]
  projection = reuse ? File.binread(File.join(output, path)) : source.gsub(/[^\n]/, " ")
  spans = reuse ? prior.fetch("selected_spans") : []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
  end
  line_end = source.index("\n", owner.location.start_offset)
  copy.call(Prism::Location.new(parsed.source, owner.location.start_offset, line_end - owner.location.start_offset), "source_owner")
  copy.call(owner.end_keyword_loc, "source_owner_end")
  methods = owner.body.body.grep(Prism::DefNode)
  selected = methods.select { |node| spec.fetch(:methods, []).include?(node.name) }
  missing = spec.fetch(:methods, []) - selected.map(&:name)
  raise "missing method roots #{path}: #{missing}" unless missing.empty?
  loop do
    calls = selected.flat_map { |node| descendants(node).grep(Prism::CallNode).map(&:name) }.uniq
    more = methods.select { |node| calls.include?(node.name) && !selected.include?(node) }
    break if more.empty?
    selected.concat(more)
  end
  selected.each { |node| copy.call(node.location, "whole_source_read_method:#{node.name}") }
  owner.body.body.grep(Prism::CallNode).each do |node|
    scope = node.name == :scope && spec.fetch(:scopes, []).include?(node.arguments.arguments.first.unescaped.to_sym)
    mixin = node.name == :include && spec.fetch(:includes, []).include?(node.arguments.arguments.first.slice)
    association = %i[belongs_to has_many has_one].include?(node.name) && spec.fetch(:associations, []).include?(node.arguments.arguments.first.unescaped)
    if scope || mixin || association || spec.fetch(:declarations, []).include?(node.name)
      copy.call(node.location, "source_declaration:#{node.name}")
    end
  end
  raise "invalid projection #{path}" unless Prism.parse(projection).success?
  File.binwrite(File.join(output, path), projection)
  map.reject! { |entry| entry["generated"] == path }
  candidates.reject! { |entry| entry["generated"] == path }
  entry = {source: path, generated: path, source_sha256: sha,
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "Partial latest read API roots only; whole source bodies retained, no runtime-value specialization or broader helper API acceptance"}
  if candidate
    entry[:source_root] = "compat/discourse"
    candidates << entry
  else
    map << entry
  end
end
File.write(maps_path, JSON.pretty_generate(map) + "\n")
File.write(candidate_path, JSON.pretty_generate(candidates) + "\n")
