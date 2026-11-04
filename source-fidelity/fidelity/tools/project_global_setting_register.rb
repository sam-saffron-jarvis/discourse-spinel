# frozen_string_literal: true
# Audited original GlobalSetting factory/provider projections. Default:
# register + EnvProvider. cache: all four factories + complete providers and
# actual defaults resource. NOT Rails/SiteSetting/YAML/plugin/security boot.
# No method text, getter body, provider lookup or coerce is replaced.
require "prism"
require "json"
require "digest"
require "fileutils"
root, output, mode = ARGV
mode ||= "register"
raise "unknown projection mode" unless %w[register cache].include?(mode)
methods = mode == "cache" ? %i[register load_defaults add_default configure!] : %i[register]
providers = mode == "cache" ? %w[BaseProvider EnvProvider FileProvider BlankProvider] : %w[BaseProvider EnvProvider]
path = "app/models/global_setting.rb"
source = File.binread(File.join(root, path))
parsed = Prism.parse(source)
raise "invalid original GlobalSetting" unless parsed.success?
owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "GlobalSetting" }
raise "missing GlobalSetting" unless owner
projected = source.gsub(/[^\n]/, " ")
spans = []
copy = lambda do |location, role|
  projected[location.start_offset, location.length] = source[location.start_offset, location.length]
  spans << { role: role, start_byte: location.start_offset, end_byte: location.end_offset,
             start_line: location.start_line, end_line: location.end_line,
             text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length]) }
end
ending = source.index("\n", owner.location.start_offset)
copy.call(Prism::Location.new(parsed.source, owner.location.start_offset, ending - owner.location.start_offset), "owner")
copy.call(owner.end_keyword_loc, "owner_end")
methods.each do |name|
  selected = owner.body.body.select { |node| node.is_a?(Prism::DefNode) && node.receiver&.is_a?(Prism::SelfNode) && node.name == name }
  raise "ambiguous/missing original #{name}" unless selected.length == 1
  copy.call(selected.first.location, "method:self.#{name}")
end
providers.each do |name|
  nested = owner.body.body.select { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == name }
  raise "ambiguous/missing #{name}" unless nested.length == 1
  copy.call(nested.first.location, "complete_nested_provider:#{name}")
end
accessor = owner.body.body.select { |node| node.is_a?(Prism::SingletonClassNode) && node.expression.is_a?(Prism::SelfNode) && node.body.body.any? { |call| call.is_a?(Prism::CallNode) && call.name == :attr_accessor && call.arguments&.arguments&.any? { |arg| arg.is_a?(Prism::SymbolNode) && arg.value == "provider" } } }
raise "ambiguous/missing original provider accessor" unless accessor.length == 1
copy.call(accessor.first.location, "original_provider_accessor")
destination = "app/models/global_setting.rb"
FileUtils.mkdir_p(File.join(output, "app/models"))
File.binwrite(File.join(output, destination), projected)
manifest = [{ source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
              generated_sha256: Digest::SHA256.hexdigest(projected), selected_spans: spans,
              limitation: "PURE register+actual EnvProvider/coerce ONLY; not configure/load_defaults/YAML/provider/bootstrap/plugins/SiteSetting/security/019" }]
if mode == "cache"
  resource = "config/discourse_defaults.conf"
  bytes = File.binread(File.join(root, resource))
  FileUtils.mkdir_p(File.join(output, "config"))
  File.binwrite(File.join(output, resource), bytes)
  manifest << { source: resource, generated: resource, role: "complete_original_resource",
                source_sha256: Digest::SHA256.hexdigest(bytes), generated_sha256: Digest::SHA256.hexdigest(bytes) }
  manifest.first[:limitation] = "Original register/add_default/configure/load_defaults + complete providers and defaults resource closure ONLY; not Rails boot/SiteSetting/YAML/plugin/User/security/019"
end
File.write(File.join(output, "projection-map.json"), JSON.pretty_generate(manifest) + "\n")
