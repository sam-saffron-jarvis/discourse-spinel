# frozen_string_literal: true
# Audited original activation producer. Whole-method mode is a dependency
# measurement, NOT a boot. --eval-prefix measures ONLY original935: the first
# statement of activate!, without executing its filesystem-producing suffix.
require "prism"
require "json"
require "digest"
require "fileutils"
root, output, mode = ARGV
raise "unknown mode" unless [nil, "--eval-prefix", "--metadata-prefix"].include?(mode)
maps = []
{
  "lib/plugin.rb" => ["Plugin", []],
  "lib/plugin/instance.rb" => ["Plugin::Instance", %i[initialize activate! after_initialize notify_after_initialize reloadable_patch enabled_site_setting]],
}.each do |path, (owner, methods)|
  # These suffix consumers have their own complete-method measurement above;
  # they cannot be reached by the isolated first-statement prefix.
  methods -= %i[notify_after_initialize reloadable_patch] if mode == "--eval-prefix"
  methods = %i[initialize parse_from_source] if mode == "--metadata-prefix" && owner == "Plugin::Instance"
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  raise "invalid original #{path}" unless parsed.success?
  declaration = parsed.value.statements.body.find do |node|
    (node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)) && node.constant_path.slice == owner
  end
  raise "missing #{owner}" unless declaration
  projected = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projected[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
               start_line: location.start_line, end_line: location.end_line,
               text_sha256: Digest::SHA256.hexdigest(location.slice) }
  end
  line_end = source.index("\n", declaration.location.start_offset)
  copy.call(Prism::Location.new(parsed.source, declaration.location.start_offset, line_end - declaration.location.start_offset), "original_owner_header")
  copy.call(declaration.end_keyword_loc, "original_owner_end")
  body = declaration.body&.body || []
  methods.each do |name|
    selected = body.select do |node|
      node.is_a?(Prism::DefNode) && node.name == name &&
        (name == :parse_from_source ? node.receiver&.slice == "self" : node.receiver.nil?)
    end
    raise "ambiguous/missing #{owner}##{name}" unless selected.length == 1
    node = selected.first
    if mode == "--eval-prefix" && name == :activate!
      first = node.body.body.first
      raise "activation first statement changed" unless first.is_a?(Prism::CallNode) && first.name == :instance_eval
      line_end = source.index("\n", node.location.start_offset)
      copy.call(Prism::Location.new(parsed.source, node.location.start_offset, line_end - node.location.start_offset), "PARTIAL_activate_header")
      copy.call(first.location, "original_evaluation_statement_ONLY")
      copy.call(node.end_keyword_loc, "PARTIAL_activate_end")
    else
      copy.call(node.location, "whole_method:#{name}")
    end
  end
  if owner == "Plugin::Instance"
    readers = body.select do |node|
      node.is_a?(Prism::CallNode) && node.name == :each && node.block.is_a?(Prism::BlockNode) &&
        node.block.body&.body&.any? { |item| item.is_a?(Prism::CallNode) && item.name == :class_eval }
    end
    raise "ambiguous/missing memo-reader producer" unless readers.length == 1
    copy.call(readers.first.location, "original_memo_reader_loop")
    accessors = body.select { |node| node.is_a?(Prism::CallNode) && node.name == :attr_accessor && node.arguments&.arguments&.any? { |arg| arg.is_a?(Prism::SymbolNode) && arg.unescaped == "path" } }
    raise "ambiguous/missing path declaration" unless accessors.length == 1
    copy.call(accessors.first.location, "original_path_metadata_declaration")
  end
  target = "app/models/" + owner.split("::").map { |name| name.gsub(/([a-z])([A-Z])/, '\\1_\\2').downcase }.join("/") + ".rb"
  FileUtils.mkdir_p(File.dirname(File.join(output, target)))
  File.binwrite(File.join(output, target), projected)
  maps << { source: path, generated: target, source_sha256: Digest::SHA256.hexdigest(source),
            generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
            limitation: mode == "--eval-prefix" ? "PARTIAL activate! first statement ONLY; never activation acceptance" : "whole selected original producer methods; remaining class/dependencies/effects NOT admitted" }
end
if mode == "--metadata-prefix"
  { "lib/plugin/metadata.rb" => "app/models/plugin/metadata.rb", "config/official_plugins.json" => "config/official_plugins.json" }.each do |path, target|
    source = File.binread(File.join(root, path))
    FileUtils.mkdir_p(File.dirname(File.join(output, target)))
    File.binwrite(File.join(output, target), source)
    sha = Digest::SHA256.hexdigest(source)
    maps << { source: path, generated: target, source_sha256: sha, generated_sha256: sha,
              selected_spans: [{ role: "complete_original_file", start_byte: 0, end_byte: source.bytesize, text_sha256: sha }],
              limitation: "complete metadata source/resource with whole original parse_from_source; NOT activation or provider/settings bootstrap" }
  end
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(maps) + "\n")
