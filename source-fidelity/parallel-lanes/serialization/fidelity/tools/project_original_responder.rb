# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "prism"

source_root, output_root = ARGV
abort "usage: project_original_responder.rb SOURCE_ROOT OUTPUT_ROOT" unless source_root && output_root
source_path = "lib/topic_list_responder.rb"
source = File.binread(File.join(source_root, source_path))
parse = Prism.parse(source)
abort "invalid pinned original source" unless parse.success?

def all_nodes(node, list = [])
  list << node
  node.compact_child_nodes.each { |child| all_nodes(child, list) }
  list
end

nodes = all_nodes(parse.value)
mod = nodes.find { |n| n.is_a?(Prism::ModuleNode) && n.constant_path.slice == "TopicListResponder" }
abort "missing original TopicListResponder" unless mod
method = mod.body.body.select { |n| n.is_a?(Prism::DefNode) && n.name == :respond_with_list }
abort "expected one original respond_with_list" unless method.length == 1
method = method.first
branch = all_nodes(method).select do |n|
  n.is_a?(Prism::CallNode) && n.name == :json && n.receiver&.slice == "format"
end
abort "expected one original format.json branch" unless branch.length == 1

projected = source.gsub(/[^\n]/, " ")
spans = []
copy = lambda do |location, role|
  projected[location.start_offset, location.length] = source[location.start_offset, location.length]
  spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
             start_line: location.start_line, end_line: location.end_line,
             sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length]) }
end
header_end = source.index("\n", mod.location.start_offset)
copy.call(Prism::Location.new(parse.source, mod.location.start_offset, header_end - mod.location.start_offset), "module_header")
copy.call(method.location, "original_method:respond_with_list")
copy.call(branch.first.location, "original_format_json_branch")
copy.call(mod.end_keyword_loc, "module_end")
output_path = "app/controllers/concerns/topic_list_responder.rb"
output = File.join(output_root, output_path)
FileUtils.mkdir_p(File.dirname(output))
File.binwrite(output, projected)
manifest = { source: source_path, generated: output_path,
             source_sha256: Digest::SHA256.hexdigest(source),
             generated_sha256: Digest::SHA256.hexdigest(projected),
             original_revision: "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8",
             selected_spans: spans,
             transformation: "space-unselected-source-bytes-only; original respond_with_list body retained byte-for-byte",
             unsupported_survey_output: false }
File.write(File.join(output_root, "responder-projection.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
