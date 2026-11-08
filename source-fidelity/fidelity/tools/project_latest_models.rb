# frozen_string_literal: true
# Compile-only READ declaration/method projections from real full source.
# Actual catalog columns and whole source methods; never fake permission data.
require "prism"
require "json"
require "digest"

def descendants(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| descendants(child, result) }
  result
end

root, output, candidate_root = ARGV
# Method roots come from the whole-method latest/list/lookup callers. Any
# same-owner calls in selected methods add their complete bodies as well.
specs = {
  "User" => [%i[admin?], %i[primary_group flair_group uploaded_avatar]],
  "Group" => [[], %i[flair_upload]],
  "Tag" => [[], %i[topic_tags topics]],
  "TopicTag" => [[], %i[topic tag]],
  "SharedDraft" => [[], %i[topic category]],
  "TopicUser" => [%i[notification_levels lookup_for], %i[topic user]],
  "CategoryUser" => [%i[notification_levels default_notification_level indirectly_muted_category_ids lookup_for], %i[category user]],
  "TagUser" => [%i[notification_levels lookup], %i[tag user]],
  "DismissedTopicUser" => [%i[lookup_for], %i[topic user]],
  "PostAction" => [%i[lookup_for], %i[post user post_action_type target_user]],
  "PostActionType" => [%i[types initialize_flag_settings], []],
  "Post" => [[], %i[topic user]],
  "Flag" => [[], []],
  "TagGroup" => [[], %i[tag_group_memberships tags tag_group_permissions]],
  "TagGroupMembership" => [[], %i[tag tag_group]],
  "TagGroupPermission" => [%i[permission_types], %i[tag_group group]],
  "BaseTimer" => [%i[types], []],
  "TopicCustomField" => [[], %i[topic]],
  "TopicTimer" => [[], %i[user topic category]],
}
maps_path = File.join(output, "projection-map.json")
maps = JSON.parse(File.read(maps_path))
candidate_maps = []
specs.each do |owner_name, (roots, associations)|
  basename = owner_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  path = "app/models/#{basename}.rb"
  # Keep the historical query/list projection's candidate boundary finite.
  # Serializer-only User/Group/Tag adaptations are selected later by the
  # separately audited project_serializer_dependencies, not by file presence.
  candidate_models = %w[PostActionType PostAction CategoryUser TopicUser DismissedTopicUser]
  candidate = candidate_root && candidate_models.include?(owner_name) && File.file?(File.join(candidate_root, path))
  source = File.binread(File.join(candidate ? candidate_root : root, path))
  parsed = Prism.parse(source)
  raise "invalid original model #{path}" unless parsed.success?
  owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == owner_name }
  raise "missing owner #{owner_name}" unless owner
  methods = owner.body.body.grep(Prism::DefNode)
  singleton_classes = owner.body.body.grep(Prism::SingletonClassNode)
  methods += singleton_classes.flat_map { |node| node.body.body.grep(Prism::DefNode) }
  selected = methods.select { |node| roots.include?(node.name) }
  raise "missing source methods #{owner_name}:#{roots - selected.map(&:name)}" unless (roots - selected.map(&:name)).empty?
  loop do
    names = selected.flat_map { |node| descendants(node).grep(Prism::CallNode).map(&:name) }.uniq
    additions = methods.select { |node| names.include?(node.name) && !selected.include?(node) }
    break if additions.empty?
    selected.concat(additions)
  end
  projection = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
  end
  header = lambda do |node, role|
    last = source.index("\n", node.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, node.location.start_offset, last - node.location.start_offset), role)
    copy.call(node.end_keyword_loc, "#{role}_end")
  end
  header.call(owner, "original_model_header")
  singleton_classes.each do |node|
    if selected.any? { |method| node.body.body.include?(method) }
      header.call(node, "original_singleton_scope")
      node.body.body.each do |statement|
        if statement.is_a?(Prism::CallNode) && %i[attr_reader attr_accessor].include?(statement.name)
          copy.call(statement.location, "original_singleton_accessor")
        end
      end
    end
  end
  selected.each { |node| copy.call(node.location, "whole_read_method:#{node.name}") }
  owner.body.body.each do |node|
    next unless node.is_a?(Prism::CallNode)
    if node.name == :table_name= && node.receiver&.slice == "self"
      copy.call(node.location, "original_table_mapping")
    elsif node.name == :initialize_flag_settings && owner_name == "PostActionType"
      copy.call(node.location, "original_read_state_initialization")
    elsif node.name == :include && node.arguments&.arguments&.first&.slice == "Trashable"
      copy.call(node.location, "original_soft_delete_concern")
    elsif node.name == :default_scope
      copy.call(node.location, "original_default_scope")
    elsif %i[belongs_to has_one has_many].include?(node.name) && associations.include?(node.arguments&.arguments&.first&.unescaped&.to_sym)
      copy.call(node.location, "original_association:#{node.arguments.arguments.first.unescaped}")
    end
  end
  # Only real source constants referenced by selected bodies (or the core
  # Group ID map) are included, never an observed database value.
  referenced = selected.flat_map { |node| descendants(node).grep(Prism::ConstantReadNode).map(&:name) }
  owner.body.body.grep(Prism::ConstantWriteNode).each do |node|
    copy.call(node.location, "original_constant:#{node.name}") if referenced.include?(node.name) || (owner_name == "Group" && node.name == :AUTO_GROUPS) || owner_name == "PostActionType"
  end
  File.binwrite(File.join(output, path), projection)
  maps = maps.reject { |entry| entry["generated"] == path }
  entry = {source: path, generated: path, source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "READ declaration/method projection ONLY; omitted lifecycle/write/other business APIs NOT admitted"}
  if candidate
    entry[:source_root] = "compat/discourse"
    entry[:limitation] = "PATCHED application read-model projection ONLY; not immutable-source proof or full API admission"
    candidate_maps << entry
  else
    maps << entry
  end
end
File.write(maps_path, JSON.pretty_generate(maps) + "\n")
File.write(File.join(output, "candidate-model-projections.json"), JSON.pretty_generate(candidate_maps) + "\n")
