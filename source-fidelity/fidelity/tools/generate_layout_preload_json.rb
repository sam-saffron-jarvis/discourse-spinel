# frozen_string_literal: true
require "prism"
require "digest"
require "json"
require "open3"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
path = "app/helpers/application_helper.rb"
source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
raise "original layout helper changed" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
spans = []
methods = %i[escape_unicode preloaded_json].map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == name }
  raise "layout helper missing #{name}" unless node
  spans << {method: name, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
            text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
text = "# frozen_string_literal: true\n# GENERATED exact isolated methods; standalone JSON unit context, not full Rails encoder.\nrequire \"json\"\nmodule PortableLayoutPreloadMethods\n#{methods.join("\n\n")}\nend\n"
raise "invalid layout helper" unless Prism.parse(text).success?
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_layout_preload_json.rb"), text)
File.write(ARGV.fetch(0), text)
proof = {pin: pin, source: path, source_sha256: Digest::SHA256.hexdigest(source), selected_spans: spans,
  candidate_sha256: Digest::SHA256.hexdigest(text), transformations: [],
  context: "Explicit isolated preloader of unit serialized strings/nil; standalone JSON encoder, no Rails/AS/Oj boot or captured production preloads",
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_layout_preload_json.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated exact isolated layout preload JSON helpers"
