# frozen_string_literal: true
require "prism"
require "json"
require "digest"
require "open3"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
sources = {}
spans = []
read = lambda do |path|
  source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "original CSP source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
  sources[path] = Digest::SHA256.hexdigest(source)
  source
end
select = lambda do |path, &predicate|
  found = []
  visit = lambda do |node|
    found << node if predicate.call(node)
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(read.call(path)).value)
  raise "CSP source boundary changed #{path}" unless found.length == 1
  node = found.first
  spans << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
default = select.call("lib/content_security_policy/default.rb") { |n| n.is_a?(Prism::ClassNode) && n.constant_path.slice == "Default" }
builder = select.call("lib/content_security_policy/builder.rb") { |n| n.is_a?(Prism::ClassNode) && n.constant_path.slice == "Builder" }
build = select.call("lib/content_security_policy.rb") { |n| n.is_a?(Prism::DefNode) && n.name == :build }
setting_extension = select.call("lib/content_security_policy/extension.rb") { |n| n.is_a?(Prism::DefNode) && n.name == :site_setting_extension }
framework, package = FidelitySourcePackage.member(root, "actionpack-8.1.4", "lib/action_dispatch/http/content_security_policy.rb")
framework_spans = []
visit = lambda do |node|
  if (node.is_a?(Prism::DefNode) && %i[build apply_mappings apply_mapping build_directives validate build_directive resolve_source upgrade_insecure_requests].include?(node.name)) ||
       (node.is_a?(Prism::ConstantWriteNode) && %i[MAPPINGS DIRECTIVES HASH_SOURCE_ALGORITHM_PREFIXES].include?(node.name))
    framework_spans << {name: node.name, node_type: node.class.name, source: "actionpack-8.1.4/#{package[:member]}", start_byte: node.location.start_offset,
      end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  end
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(framework).value)
# The reference methods remain unmodified, including the real Default and
# actual Builder#build dispatch to the genuine ActionDispatch serializer.
original = "class ContentSecurityPolicy\n#{default}\n#{builder}\n#{build}\nmodule Extension\nextend self\n#{setting_extension}\nend\nend\n"
File.write(ARGV.fetch(0), original)
lowered_default = default.sub('def initialize(report_only: false)', 'def initialize(context:, report_only: false)\n      @context = context'.gsub('\\n', "\n"))
lowered_default = lowered_default.gsub("SiteSetting.", "@context.settings.").gsub("GlobalSetting.", "@context.assets.").gsub("Discourse.base_path", "@context.base_path").gsub("EmbeddableHost.pluck(:host)", "@context.host_store.pluck(:host)")
lowered_default = lowered_default.gsub('@context.settings.content_security_policy_report_uri.presence', 'PortableCspUnitProfile.presence(@context.settings.content_security_policy_report_uri)')
lowered_default = lowered_default.gsub('@context.assets.s3_asset_cdn_url.presence', 'PortableCspUnitProfile.presence(@context.assets.s3_asset_cdn_url)')
lowered_default = lowered_default.gsub('@context.assets.s3_cdn_url.present?', '!PortableCspUnitProfile.blank?(@context.assets.s3_cdn_url)')
lowered_default = lowered_default.gsub('@context.assets.cdn_url.present?', '!PortableCspUnitProfile.blank?(@context.assets.cdn_url)')
lowered_default = lowered_default.gsub('report_uri.present?', '!PortableCspUnitProfile.blank?(report_uri)')
lowered_builder = builder.sub('def initialize(base_url:, report_only: false)', 'def initialize(context:, base_url:, report_only: false)\n      @context = context'.gsub('\\n', "\n"))
lowered_builder = lowered_builder.sub('Default.new(report_only: report_only)', 'Default.new(context: context, report_only: report_only)')
lowered_builder = lowered_builder.sub('def <<(extension)', 'def <<(extension)\n      PortableCspUnitProfile.validate_extension!(extension)'.gsub('\\n', "\n"))
lowered_builder = lowered_builder.gsub('policy.public_send(directive, *sources)', 'policy.set_source_directive(directive.to_s.gsub("_", "-"), sources)')
lowered_builder = lowered_builder.sub('policy.public_send(directive, sources)', 'raise ArgumentError, "unsupported non-array built directive profile"')
lowered_builder = lowered_builder.sub('source.starts_with?("/")', 'source.start_with?("/")')
# With the admitted String-only extension profile this method is only prefix
# testing/concatenation and cannot raise URI::ParseError (not defined by URI).
lowered_builder = lowered_builder.sub("    rescue URI::ParseError\n      source\n", "")
lowered_builder = lowered_builder.sub('Rails.logger.warn(<<~MSG.squish)', '@context.logger.warn((<<~MSG).gsub(/[[:space:]]+/, " ").strip)')
lowered_build = build.sub('Builder.new(base_url: base_url, report_only: report_only)', 'Builder.new(context: @context, base_url: base_url, report_only: report_only)')
lowered_build = lowered_build.gsub('Extension.theme_extensions(theme_id)', '@context.extensions.theme_extensions(theme_id)').gsub('Extension.plugin_extensions', '@context.extensions.plugin_extensions').gsub('Extension.site_setting_extension', '@context.extensions.site_setting_extension')
candidate = "# frozen_string_literal: true\n# GENERATED original CSP construction; explicit UNIT data/acquisition context.\nclass ContentSecurityPolicy\ndef initialize(context)\n@context = context\nend\n#{lowered_default}\n#{lowered_builder}\n#{lowered_build}\nend\n"
raise "invalid lowered CSP construction" unless Prism.parse(candidate).success?
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_csp_policy.rb"), candidate)
proof = {pin: pin, original_source_sha256: sources, selected_spans: spans, actionpack_package: package, framework_spans: framework_spans,
  candidate_sha256: Digest::SHA256.hexdigest(candidate), original_projection_sha256: Digest::SHA256.hexdigest(original),
  runtime_sha256: Digest::SHA256.file(File.join(root, "roundhouse/runtime/ruby/action_dispatch/content_security_policy.rb")).hexdigest,
  transformations: ["Original Default+Builder+orchestrator retained, supplied unit context replaces globals/acquisition only",
    "Actual ActionDispatch serializer reused via typed directive-DSL bridge, not a separate header formatter",
    "Actual fast_blank String/nil presence profile; original POSIX whitespace validation preserved",
    "Original squished warn text lowers to equivalent whitespace substitution/strip and real owned Logger effect",
    "String-only extension admission excludes unreachable URI::ParseError rescue; unsupported profiles refuse before mutation"],
  context: "UNIT settings/base URLs/EmbeddableHost vectors/extensions/log fixtures, never real Site/settings/theme preloads or full Extension baking",
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_csp_policy.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated source-backed CSP Default/Builder and verified ActionDispatch provenance"
