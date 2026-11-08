# frozen_string_literal: true
require "prism"
require "digest"
require "json"
require "open3"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
path = "app/helpers/application_helper.rb"
source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
raise "original ApplicationHelper changed" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
spans = []
original = %i[preload_script preload_script_url module_preloads_for add_resource_preload_list].map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |item| item.name == name }
  raise "missing original helper #{name}" unless node
  spans << {method: name, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
            text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
candidate = original.map do |text|
  text = text.gsub("EmberAssets.script_chunks", "asset_chunks")
  text = text.sub('controller.instance_variable_get(:@asset_preload_links)', 'controller.asset_preload_links')
  text = text.sub('controller.instance_variable_set(:@asset_preload_links, [])', '(controller.asset_preload_links = [])')
  text = text.sub('if extra_attrs.present?', 'if extra_attrs && !extra_attrs.empty?')
  text = text.sub('modulepreload_tags.join("\\n").html_safe', 'ActionView::HtmlFragment.new(modulepreload_tags.join("\\n"))')
  text = text.sub('<<~HTML.html_safe', 'ActionView::HtmlFragment.new(<<~HTML)')
  text
end
header = "# frozen_string_literal: true\n# GENERATED isolated helper dependency, not an HTML request.\n"
text = header + "require \"erb\"\nmodule PortableAssetPreloadMethods\n#{candidate.join("\n\n")}\nend\n"
raise "invalid helper projection" unless Prism.parse(text).success?
target = File.join(root, "fidelity/compat/discourse/lib/portable_asset_preloads.rb")
File.write(target, text)
if ARGV[0]
  File.write(ARGV[0], header + "module PortableAssetPreloadMethods\n#{original.join("\n\n")}\nend\n")
end
proof = {pin: pin, source: path, source_sha256: Digest::SHA256.hexdigest(source), selected_spans: spans,
  candidate_sha256: Digest::SHA256.hexdigest(text),
  transformations: ["Explicit supplied asset_chunks instead of EmberAssets global lookup",
    "Typed controller asset_preload_links access replaces same original ivar read/lazy assignment",
    "Generated nonempty attrs string presence is nil/nonempty check",
    "SafeBuffer result represented by typed ActionView::HtmlFragment, not silently plain String"],
  context: "Caller supplies unit URLs/nonce/graph and isolated resource-preload controller state; NOT production settings or nonce",
  exclusions: ["Rails boot", "PG/cache effects", "real URL/CDN resolver", "full SafeBuffer API", "safe-buffer attribute input"],
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_asset_preloads.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated original-backed isolated asset preload helpers"
