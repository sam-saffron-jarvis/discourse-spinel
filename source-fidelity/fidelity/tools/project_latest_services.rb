# frozen_string_literal: true
# Compile-only complete-method projections for the remaining real core services.
# Every selected body/constant/accessor is copied, not invented or simplified.
require "prism"
require "json"
require "digest"

def service_nodes(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| service_nodes(child, result) }
  result
end

root, output, candidate_root = ARGV
specs = {
  "lib/discourse_plugin_registry.rb" => ["DiscoursePluginRegistry", %i[apply_modifier]],
  "lib/topics_filter.rb" => ["TopicsFilter", %i[initialize filter_status option_info]],
  "lib/search.rb" => ["Search", %i[ts_query]],
  "lib/discourse_tagging.rb" => ["DiscourseTagging", %i[visible_tags hidden_tag_names]],
  "app/models/global_setting.rb" => ["GlobalSetting", %i[skip_db? skip_db= skip_redis? skip_redis=]],
  "lib/discourse.rb" => ["Discourse", %i[cache redis redis=]],
}
maps_path = File.join(output, "projection-map.json")
maps = JSON.parse(File.read(maps_path))
candidate_maps_path = File.join(output, "candidate-model-projections.json")
candidate_maps = File.file?(candidate_maps_path) ? JSON.parse(File.read(candidate_maps_path)) : []
specs.each do |path, (owner_name, roots)|
  if owner_name == "Discourse" && candidate_root
    # The shared readonly flag view can remove this dependency entirely. Check
    # the ACTUAL already-projected callers, not a current cache/setting value.
    callers = Dir[File.join(output, "app/models/**/*.rb")].reject { |file| File.basename(file) == "discourse.rb" }
    needed = callers.any? do |file|
      tree = Prism.parse_file(file)
      raise "invalid caller source #{file}" unless tree.success?
      service_nodes(tree.value).any? { |node| node.is_a?(Prism::ConstantReadNode) && node.name == :Discourse }
    end
    unless needed
      destination = "app/models/discourse.rb"
      maps = maps.reject { |entry| entry["generated"] == destination }
      candidate_maps = candidate_maps.reject { |entry| entry["generated"] == destination }
      File.delete(File.join(output, destination)) if File.file?(File.join(output, destination))
      next
    end
  end
  candidate = candidate_root && File.file?(File.join(candidate_root, path))
  roots = roots + [:topic_preloader_associations] if candidate && owner_name == "DiscoursePluginRegistry"
  source = File.binread(File.join(candidate ? candidate_root : root, path))
  roots = roots - %i[redis redis=] if owner_name == "Discourse" && !candidate
  parsed = Prism.parse(source)
  raise "invalid source #{path}" unless parsed.success?
  owner = parsed.value.statements.body.find do |node|
    (node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)) && node.constant_path.slice == owner_name
  end
  raise "missing owner #{owner_name}" unless owner
  singleton_classes = owner.body.body.grep(Prism::SingletonClassNode)
  direct = owner.body.body.grep(Prism::DefNode)
  class_methods = direct.select { |node| node.receiver&.slice == "self" }
  instance_methods = direct.select { |node| node.receiver.nil? }
  class_methods += singleton_classes.flat_map { |node| node.body.body.grep(Prism::DefNode) }
  methods = class_methods + instance_methods
  selected = methods.select { |node| roots.include?(node.name) }
  raise "missing service roots #{owner_name}:#{roots - selected.map(&:name)}" unless (roots - selected.map(&:name)).empty?
  # Search.ts_query is a class API. The same-named instance convenience method
  # is NOT its dependency; preserve actual ownership rather than conflating it.
  selected = selected.select { |node| class_methods.include?(node) } if owner_name == "Search"
  loop do
    additions = []
    selected.each do |method|
      own_methods = class_methods.include?(method) ? class_methods : methods
      service_nodes(method).grep(Prism::CallNode).each do |call|
        # External object calls are not a reason to select an unrelated
        # same-named service method. Bare/self/owner calls retain the closure.
        receiver = call.receiver&.slice
        next unless receiver.nil? || receiver == "self" || receiver == owner_name || receiver == "self.class"
        candidates = receiver == owner_name || receiver == "self.class" ? class_methods : own_methods
        additions.concat(candidates.select { |node| node.name == call.name && !selected.include?(node) })
      end
    end
    additions.uniq!
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
  header.call(owner, "original_service_owner")
  singleton_classes.each do |node|
    header.call(node, "original_singleton_owner") if selected.any? { |method| node.body.body.include?(method) }
  end
  selected.each { |node| copy.call(node.location, "whole_service_method:#{node.name}") }
  if owner_name == "Discourse" && candidate
    owner.body.body.each do |node|
      if service_nodes(node).any? { |part| part.is_a?(Prism::ClassVariableWriteNode) && part.name == :@@redis }
        copy.call(node.location, "source_redis_class_variable_initialization") unless node.is_a?(Prism::DefNode)
      end
    end
  end
  # Close over source-owned constant references, not all unrelated declarations
  # (e.g. Discourse's authenticator construction is not a cache dependency).
  # Every selected constant's full body and referenced constants are retained.
  constants = owner.body.body.grep(Prism::ConstantWriteNode)
  used_constants = selected.flat_map { |node| service_nodes(node).grep(Prism::ConstantReadNode).map(&:name) }.uniq
  loop do
    dependencies = constants.select { |node| used_constants.include?(node.name) }.flat_map do |node|
      service_nodes(node).grep(Prism::ConstantReadNode).map(&:name)
    end
    updated = (used_constants + dependencies).uniq
    break if updated == used_constants
    used_constants = updated
  end

  # Preserve actual visibility and accessor declarations, including Discourse's
  # real redis writer. This does NOT fabricate a Redis connection/bootstrap.
  owner.body.body.grep(Prism::CallNode).each do |node|
    if %i[cattr_accessor mattr_accessor].include?(node.name)
      names = node.arguments&.arguments&.filter_map { |argument| argument.unescaped.to_sym if argument.respond_to?(:unescaped) } || []
      used = roots + selected.flat_map do |method|
        service_nodes(method).filter_map do |part|
          if part.is_a?(Prism::ClassVariableReadNode) || part.is_a?(Prism::ClassVariableWriteNode)
            part.name.to_s.delete_prefix("@@").to_sym
          elsif part.is_a?(Prism::CallNode)
            part.name
          end
        end
      end
      copy.call(node.location, "original_service_declaration:#{node.name}") if names.any? { |name| used.include?(name) }
    elsif node.name == :private_class_method
      names = node.arguments&.arguments&.filter_map { |argument| argument.unescaped.to_sym if argument.respond_to?(:unescaped) } || []
      copy.call(node.location, "original_service_declaration:#{node.name}") if !names.empty? && (names - selected.map(&:name)).empty?
    elsif node.name == :private_constant
      names = node.arguments&.arguments&.filter_map { |argument| argument.unescaped.to_sym if argument.respond_to?(:unescaped) } || []
      copy.call(node.location, "original_service_declaration:#{node.name}") if !names.empty? && (names - used_constants).empty?
    elsif %i[attr_reader attr_accessor private protected public].include?(node.name)
      copy.call(node.location, "original_service_declaration:#{node.name}")
    end
  end
  constants.select { |node| used_constants.include?(node.name) }.each do |node|
    # Prism's assignment location ends at the heredoc opener, not its later
    # content/terminator. Preserve those real source bytes too, never invent a
    # closing token or a blank SQL constant to make the projection parse.
    last = service_nodes(node).filter_map do |part|
      part.closing_loc.end_offset if part.respond_to?(:closing_loc) && part.closing_loc
    end.max
    finish = [node.location.end_offset, last || 0].max
    location = Prism::Location.new(parsed.source, node.location.start_offset, finish - node.location.start_offset)
    copy.call(location, "original_service_constant:#{node.name}")
  end
  raise "invalid projected service #{owner_name}" unless Prism.parse(projection).success?
  destination = "app/models/" + File.basename(path)
  File.binwrite(File.join(output, destination), projection)
  maps = maps.reject { |entry| entry["generated"] == destination }
  entry = {source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "PARTIAL service READ method closure only; omitted APIs, state writers/boot and dependencies NOT admitted"}
  candidate_maps = candidate_maps.reject { |item| item["generated"] == destination }
  if candidate
    entry[:source_root] = "compat/discourse"
    entry[:limitation] = "PATCHED shared service method projection; not immutable-source or full service admission"
    candidate_maps << entry
  else
    maps << entry
  end
end
File.write(maps_path, JSON.pretty_generate(maps) + "\n")
File.write(candidate_maps_path, JSON.pretty_generate(candidate_maps) + "\n")
