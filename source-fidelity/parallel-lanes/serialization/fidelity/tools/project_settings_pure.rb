# frozen_string_literal: true
# Pure dependency projection ONLY: original YAML file loading and unmodified
# locale-default storage. No getter, provider, plugin, refresh, DB or cache boot.
require "prism"
require "json"
require "fileutils"
require "digest"

root, output = ARGV
specs = {
  "lib/site_settings/yaml_loader.rb" => ["SiteSettings::YamlLoader", %i[initialize load load_yaml], []],
  "lib/site_settings/defaults_provider.rb" => ["SiteSettings::DefaultsProvider", %i[initialize load_setting all_clean has_setting? has_key?], %i[DEFAULT_LOCALE DEFAULT_LOCALE_SYM]],
}
maps = []
specs.each do |path, (owner, methods, constants)|
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  raise "invalid source #{path}" unless parsed.success?
  declarations = parsed.value.statements.body
  declaration = declarations.find { |n| n.is_a?(Prism::ClassNode) && n.constant_path.slice == owner }
  raise "missing #{owner}" unless declaration
  projected = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projected[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
               start_line: location.start_line, end_line: location.end_line,
               text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length]) }
  end
  # Preserve both original namespace and class syntax, including private.
  namespace = declarations.find { |n| n.is_a?(Prism::ModuleNode) && n.constant_path.slice == "SiteSettings" }
  raise "missing namespace" unless namespace
  copy.call(namespace.location, "namespace")
  ending = source.index("\n", declaration.location.start_offset)
  copy.call(Prism::Location.new(parsed.source, declaration.location.start_offset, ending - declaration.location.start_offset), "owner")
  copy.call(declaration.end_keyword_loc, "owner_end")
  methods.each do |name|
    selected = declaration.body.body.select { |n| n.is_a?(Prism::DefNode) && n.receiver.nil? && n.name == name }
    raise "ambiguous/missing #{owner}##{name}" unless selected.length == 1
    copy.call(selected.first.location, "method:#{name}")
  end
  constants.each do |name|
    selected = declaration.body.body.select { |n| n.is_a?(Prism::ConstantWriteNode) && n.name == name }
    raise "ambiguous/missing #{owner}::#{name}" unless selected.length == 1
    copy.call(selected.first.location, "constant:#{name}")
  end
  declaration.body.body.select { |n| n.is_a?(Prism::CallNode) && n.receiver.nil? && n.name == :private }.each do |node|
    copy.call(node.location, "visibility:private")
  end
  destination = "app/models/" + File.basename(path)
  FileUtils.mkdir_p(File.join(output, "app/models"))
  File.binwrite(File.join(output, destination), projected)
  maps << { source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
            generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
            limitation: "PURE dependency subset; NOT production settings, plugin/provider/upcoming-change/getter/refresh behavior or ticket019 acceptance" }
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(maps) + "\n")
