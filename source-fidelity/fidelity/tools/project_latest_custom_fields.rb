# frozen_string_literal: true
# Source-owned readonly descriptor/preload state API. No empty concern shim and
# no lifecycle/write/cache method is admitted merely to resolve a constant.
require "prism"
require "json"
require "digest"
root, output = ARGV
path = "app/models/concerns/has_custom_fields.rb"
source = File.binread(File.join(root, path))
parsed = Prism.parse(source)
owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ModuleNode) }
projection = source.gsub(/[^\n]/, " ")
spans = []
copy = lambda do |location, role|
  projection[location.start_offset, location.length] = source[location.start_offset, location.length]
  spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
end
header = lambda do |node, role|
  line_end = source.index("\n", node.location.start_offset)
  copy.call(Prism::Location.new(parsed.source, node.location.start_offset, line_end - node.location.start_offset), role)
  copy.call(node.end_keyword_loc, "#{role}_end")
end
header.call(owner, "source_read_concern")
owner.body.body.each do |node|
  case node
  when Prism::ModuleNode
    copy.call(node.location, "source_descriptor_helpers") if node.constant_path.slice == "Helpers"
  when Prism::ClassNode
    next unless node.constant_path.slice == "FieldDescriptor"
    header.call(node, "source_descriptor_class")
    node.body.body.each do |method|
      if method.is_a?(Prism::DefNode) && %i[append_field array_type? deserialize parse_json_value].include?(method.name)
        copy.call(method.location, "whole_read_descriptor_method:#{method.name}")
      elsif method.is_a?(Prism::CallNode) && method.name == :private
        copy.call(method.location, "source_visibility")
      end
    end
  when Prism::ConstantWriteNode
    copy.call(node.location, "source_default_descriptor") if node.name == :DEFAULT_FIELD_DESCRIPTOR
  when Prism::CallNode
    if node.name == :class_methods
      copy.call(node.message_loc, "source_class_api")
      copy.call(node.block.opening_loc, "source_class_api_open")
      copy.call(node.block.closing_loc, "source_class_api_close")
      node.block.body.body.each do |method|
        if method.is_a?(Prism::DefNode) && %i[get_custom_field_descriptor custom_field_meta_data].include?(method.name)
          copy.call(method.location, "whole_descriptor_lookup_method:#{method.name}")
        elsif method.is_a?(Prism::CallNode) && method.name == :private
          copy.call(method.location, "source_class_visibility")
        end
      end
    elsif node.name == :extend || (node.name == :attr_reader && node.arguments.arguments.first.unescaped == "preloaded_custom_fields")
      copy.call(node.location, "source_read_declaration:#{node.name}")
    end
  when Prism::DefNode
    copy.call(node.location, "whole_preload_state_setter") if node.name == :set_preloaded_custom_fields
  end
end
raise "invalid read concern" unless Prism.parse(projection).success?
destination = "app/models/has_custom_fields.rb"
File.binwrite(File.join(output, destination), projection)
map_path = File.join(output, "projection-map.json")
map = JSON.parse(File.read(map_path)).reject { |entry| entry["generated"] == destination }
map << {source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
  generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
  limitation: "READ descriptor/metadata/preloaded state API only; original lifecycle/writes/generic model lookup not admitted"}
File.write(map_path, JSON.pretty_generate(map) + "\n")
