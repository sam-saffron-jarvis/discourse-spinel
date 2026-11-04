# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "prism"

source_root, output_root = ARGV
abort "usage: project_original_serialization_bridge.rb SOURCE_ROOT OUTPUT_ROOT" unless source_root && output_root

PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
SPECS = {
  "app/controllers/application_controller.rb" => [
    ["ApplicationController", %i[guardian serialize_data render_serialized render_json_dump]],
  ],
  "lib/guardian.rb" => [["Guardian", %i[initialize user]]],
}.freeze

# Copy selected Prism locations into an otherwise whitespace-masked source file.
# Keeping the original byte offsets makes byte spans and line/column locations
# directly comparable to SOURCE_LOCK, rather than locations in a synthetic file.
def project_source(source_root, output_root, path, classes)
  source = File.binread(File.join(source_root, path))
  parse = Prism.parse(source)
  abort "invalid pinned original source: #{path}" unless parse.success?
  nodes = []
  visit = lambda do |node|
    nodes << node
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(parse.value)

  projection = source.dup
  projection.bytes.each_index { |i| projection.setbyte(i, 32) unless projection.getbyte(i) == 10 }
  spans = []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source.byteslice(location.start_offset, location.length)
    spans << {
      role: role,
      start_byte: location.start_offset,
      end_byte: location.end_offset,
      start_line: location.start_line,
      end_line: location.end_line,
      sha256: Digest::SHA256.hexdigest(source.byteslice(location.start_offset, location.length)),
    }
  end

  classes.each do |class_name, methods|
    klass = nodes.find do |node|
      (node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)) &&
        node.constant_path.slice == class_name
    end
    abort "missing original #{class_name} in #{path}" unless klass
    header_end = source.index("\n", klass.location.start_offset)
    copy.call(Prism::Location.new(parse.source, klass.location.start_offset, header_end - klass.location.start_offset), "class_header:#{class_name}")
    body = klass.body&.body
    methods.each do |method_name|
      found = body.select { |node| node.is_a?(Prism::DefNode) && node.name == method_name }
      abort "expected one #{class_name}##{method_name} in #{path}, got #{found.length}" unless found.length == 1
      copy.call(found.first.location, "original_method:#{class_name}##{method_name}")
    end
    copy.call(klass.end_keyword_loc, "class_end:#{class_name}")
  end

  target = File.join(output_root, path)
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, projection)
  {
    source: path,
    generated: path,
    source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection),
    selected_spans: spans,
    transformation: "space-unselected-source-bytes-only; selected original method bytes retained exactly",
  }
end

manifest = {
  original_revision: PIN,
  projections: SPECS.map { |path, classes| project_source(source_root, output_root, path, classes) },
  test_fixture_boundary: "original controller and Guardian method bodies only; no production permission or serializer method is synthesized",
}
File.write(File.join(output_root, "serialization-bridge-projection.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
