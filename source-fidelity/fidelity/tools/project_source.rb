# frozen_string_literal: true
# Produce an explicitly ISOLATED declaration slice. This does not boot a model.
# Selected AST nodes are copied, never rewritten; line/byte positions in each
# projection are retained. Entire source inputs remain separately hash-locked.
require "prism"
require "json"
require "fileutils"
require "digest"

root, output = ARGV
specs = {
  "app/models/topic.rb" => ["Topic", [[:call, :include, "Trashable"], [:call, :belongs_to, ":category"], [:call, :scope, ":listable_topics"], [:call, :scope, ":visible"]]],
  "app/models/category.rb" => ["Category", []],
  "lib/archetype.rb" => ["Archetype", [[:def, :private_message, nil]]],
  "app/models/concerns/trashable.rb" => ["Trashable", [[:call, :extend, "ActiveSupport::Concern"], [:call, :default_scope, nil]]],
}

def nodes(node, out = [])
  out << node
  node.compact_child_nodes.each { |child| nodes(child, out) }
  out
end

maps = []
specs.each do |path, (owner, selectors)|
  source = File.binread(File.join(root, path))
  result = Prism.parse(source)
  raise "invalid source #{path}" unless result.success?
  all = nodes(result.value)
  declaration = all.find { |n| (n.is_a?(Prism::ClassNode) || n.is_a?(Prism::ModuleNode)) && n.constant_path.slice == owner }
  raise "missing #{owner}" unless declaration
  projected = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projected[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
               start_line: location.start_line, end_line: location.end_line,
               text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length]) }
  end
  # Original class/module header and its matching end; not a synthetic model.
  header_end = source.index("\n", declaration.location.start_offset)
  copy.call(Prism::Location.new(result.source, declaration.location.start_offset, header_end - declaration.location.start_offset), "owner_header")
  copy.call(declaration.end_keyword_loc, "owner_end")
  selectors.each do |kind, name, first|
    found = all.select do |node|
      if kind == :def
        node.is_a?(Prism::DefNode) && node.name == name && node.receiver&.slice == "self"
      else
        node.is_a?(Prism::CallNode) && node.name == name && (first.nil? || node.arguments&.arguments&.first&.slice == first)
      end
    end
    raise "ambiguous/missing #{path} #{name} #{first}" unless found.length == 1
    selected = found.first
    copy.call(selected.location, "#{kind}:#{name}:#{first}")
    # Keep the enclosing Concern included block syntax, not its unselected
    # declarations. The omission is explicit: only its default_scope is tested.
    if name == :default_scope
      included = all.find { |n| n.is_a?(Prism::CallNode) && n.name == :included && n.block&.location&.start_offset.to_i < selected.location.start_offset && n.location.end_offset > selected.location.end_offset }
      raise "missing included context" unless included
      copy.call(included.message_loc, "concern_included")
      copy.call(included.block.opening_loc, "concern_block_open")
      copy.call(included.block.closing_loc, "concern_block_close")
    end
  end
  target = path == "lib/archetype.rb" ? "app/models/archetype.rb" : path
  destination = File.join(output, target)
  FileUtils.mkdir_p(File.dirname(destination))
  File.binwrite(destination, projected)
  maps << { source: path, generated: target, source_sha256: Digest::SHA256.hexdigest(source),
            generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
            limitation: "Isolated declaration projection; all other bodies/DSL omitted explicitly, NOT full model boot" }
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(maps) + "\n")
