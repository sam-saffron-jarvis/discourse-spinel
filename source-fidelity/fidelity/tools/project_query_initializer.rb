# frozen_string_literal: true
# Exact original initializer/options prefix, not a replacement query. Complete
# originals are separately hash locked. Unselected bytes become spaces; every
# selected application method is copied WHOLE, preserving byte/line positions.
require "prism"
require "json"
require "digest"
require "fileutils"
root, output, mode = ARGV
maps = []
{
  "lib/topic_query.rb" => ["TopicQuery", %i[initialize public_valid_options valid_options] + (mode == "--registry" ? %i[add_custom_filter remove_custom_filter apply_custom_filters] : [])],
  "lib/guardian.rb" => ["Guardian", %i[initialize is_admin?]],
}.each do |path, (owner, methods)|
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  raise "invalid original #{path}" unless parsed.success?
  declaration = parsed.value.statements.body.find { |n| n.is_a?(Prism::ClassNode) && n.constant_path.slice == owner }
  raise "missing original #{owner}" unless declaration
  projected = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projected[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
               start_line: location.start_line, end_line: location.end_line,
               text_sha256: Digest::SHA256.hexdigest(location.slice) }
  end
  header = lambda do |node, role|
    finish = source.index("\n", node.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, node.location.start_offset, finish - node.location.start_offset), role)
    copy.call(node.end_keyword_loc, "#{role}_end")
  end
  header.call(declaration, "owner")
  body = declaration.body.body
  methods.each do |name|
    selected = body.select { |n| n.is_a?(Prism::DefNode) && n.name == name }
    raise "ambiguous/missing #{owner}##{name}" unless selected.length == 1
    copy.call(selected.first.location, "whole_method:#{name}")
  end
  if owner == "TopicQuery"
    body.select { |n| n.is_a?(Prism::CallNode) && %i[attr_accessor attr_reader].include?(n.name) }.each do |node|
      copy.call(node.location, "declaration:#{node.name}")
    end
  else
    anonymous = body.find { |n| n.is_a?(Prism::ClassNode) && n.constant_path.slice == "AnonymousUser" }
    header.call(anonymous, "AnonymousUser")
    %i[blank? admin?].each do |name|
      method = anonymous.body.body.find { |n| n.is_a?(Prism::DefNode) && n.name == name }
      copy.call(method.location, "AnonymousUser##{name}")
    end
  end
  target = "app/models/#{File.basename(path)}"
  FileUtils.mkdir_p(File.dirname(File.join(output, target)))
  File.binwrite(File.join(output, target), projected)
  maps << { source: path, generated: target, source_sha256: Digest::SHA256.hexdigest(source),
            generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
            limitation: "whole original initializer/options-method prefix ONLY; no list_latest, settings/plugin boot or page equivalence" }
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(maps) + "\n")
