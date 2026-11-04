# frozen_string_literal: true
# Original pure modifier registration/dispatch and REAL unconfigured plugin
# enabled predicate. Not plugin startup, a production registry or settings boot.
require "prism"
require "json"
require "fileutils"
require "digest"

root, output = ARGV
specs = {
  "lib/plugin.rb" => ["Plugin", []],
  "lib/plugin/instance.rb" => ["Plugin::Instance", [[:initialize, false], [:configurable?, false], [:enabled?, false], [:enabled_site_setting, false]]],
  "lib/discourse_plugin_registry.rb" => ["DiscoursePluginRegistry", [[:register_modifier, true], [:apply_modifier, true]]],
  # Declaration-only typing for the out-of-scope configured-plugin branch.
  # No getter is manufactured; this model is not loaded by the pure consumer.
  "app/models/site_setting.rb" => ["SiteSetting", []],
  "lib/site_settings/defaults_provider.rb" => ["SiteSettings::DefaultsProvider",
    [[:initialize, false], [:load_setting, false], [:all_clean, false], [:all, false],
     [:activate_upcoming_change_override, false], [:deactivate_upcoming_change_override, false]],
    %i[DEFAULT_LOCALE DEFAULT_LOCALE_SYM]],
  # Only borrow this original metadata method; no extend event or its hook is
  # performed. This is not the original SiteSetting object or a value getter.
  "lib/site_setting_extension.rb" => ["SiteSettingExtension", [[:upcoming_change_default_overrides, false]]],
}
maps = []
specs.each do |path, (owner, methods, constants)|
  source = File.binread(File.join(root, path))
  parsed = Prism.parse(source)
  raise "invalid source #{path}" unless parsed.success?
  declarations = parsed.value.statements.body
  declaration = declarations.find { |n| (n.is_a?(Prism::ClassNode) || n.is_a?(Prism::ModuleNode)) && n.constant_path.slice == owner }
  raise "missing #{owner}" unless declaration
  projected = source.gsub(/[^\n]/, " ")
  spans = []
  copy = lambda do |location, role|
    projected[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
               start_line: location.start_line, end_line: location.end_line,
               text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length]) }
  end
  ending = source.index("\n", declaration.location.start_offset)
  copy.call(Prism::Location.new(parsed.source, declaration.location.start_offset, ending - declaration.location.start_offset), "owner")
  copy.call(declaration.end_keyword_loc, "owner_end")
  namespace = declarations.find { |n| n.is_a?(Prism::ModuleNode) && n.constant_path.slice == owner.split("::").first && n != declaration }
  if namespace
    raise "namespace projection has executable members" unless namespace.body.nil? || namespace.body.body.empty?
    copy.call(namespace.location, "namespace")
  end
  (constants || []).each do |name|
    selected = declaration.body.body.select { |n| n.is_a?(Prism::ConstantWriteNode) && n.name == name }
    raise "ambiguous/missing #{owner}::#{name}" unless selected.length == 1
    copy.call(selected.first.location, "constant:#{name}")
  end
  methods.each do |name, singleton|
    selected = declaration.body.body.select { |n| n.is_a?(Prism::DefNode) && n.name == name && (singleton ? n.receiver&.slice == "self" : n.receiver.nil?) }
    raise "ambiguous/missing #{owner} #{name}" unless selected.length == 1
    copy.call(selected.first.location, "method:#{singleton ? 'self.' : ''}#{name}")
  end
  destination = "app/models/" + owner.split("::").map { |n| n.gsub(/([a-z])([A-Z])/, '\\1_\\2').downcase }.join("/") + ".rb"
  FileUtils.mkdir_p(File.dirname(File.join(output, destination)))
  File.binwrite(File.join(output, destination), projected)
  maps << { source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
            generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
            limitation: "PURE registry, actual unconfigured Plugin::Instance, original DefaultsProvider all/activation, and an original metadata method borrowed by a TEST consumer (no extend event); configured setting branch explicitly fails; no production plugin/settings/019 proof" }
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(maps) + "\n")
