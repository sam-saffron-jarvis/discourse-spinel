# frozen_string_literal: true
# Extract the manifest graph dependency, NOT the complete EmberAssets lifecycle.
require "prism"
require "digest"
require "json"
require "open3"

root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
path = "lib/ember_assets.rb"
source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
raise "missing pinned EmberAssets" unless status.success?
raise "original EmberAssets changed" unless File.binread(File.join(root, "discourse", path)) == source.b
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
raise "original asset owner changed" unless owner.constant_path.slice == "EmberAssets"
spans = []
methods = %i[script_chunks import_map logical_name deep_imports_for].map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |item| item.name == name }
  raise "original asset method missing #{name}" unless node
  spans << {source: path, method: name, start_byte: node.location.start_offset,
            end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  text = node.slice
  if name == :script_chunks
    before = <<~'SOURCE'
      def self.script_chunks(exception: true)
          raise_if_build_error! if exception
          return cache[:script_chunks] if cache[:script_chunks]

          entrypoints = {}

          manifest = read_manifest!(exception: exception)
          return {} if manifest.nil?
    SOURCE
    raise "original script_chunks boundary changed" unless text.start_with?(before)
    text = text.sub(before, "def self.script_chunks(manifest)\n    entrypoints = {}\n")
    raise "original script_chunks result changed" unless text.include?("cache[:script_chunks] = entrypoints")
    text = text.sub("cache[:script_chunks] = entrypoints", "entrypoints")
  elsif name == :import_map
    before = <<~'SOURCE'.chomp
      def self.import_map
          raise_if_build_error!
          cache[:import_map] ||= (
            read_manifest!(exception: true)&.dig("importMap") || {}
          )
    SOURCE
    raise "original import_map boundary changed" unless text.start_with?(before)
    text = text.sub(before, "def self.import_map(manifest)\n    (manifest.dig(\"importMap\") || {})")
  end
  text
end
text = <<~RUBY
  # frozen_string_literal: true
  # GENERATED from pinned EmberAssets graph methods. This is an explicit pure
  # dependency: callers supply a live parsed manifest. NOT the full EmberAssets
  # class, request/production cache, build-status/error lifecycle or HTML renderer.
  require "set"
  class PortableEmberAssetGraph
    #{methods.join("\n\n")}
  end
RUBY
raise "invalid graph candidate" unless Prism.parse(text).success?
target = File.join(root, "fidelity/compat/discourse/lib/portable_ember_asset_graph.rb")
File.binwrite(target, text)
proof = {pin: pin, source: path, source_sha256: Digest::SHA256.hexdigest(source),
         selected_spans: spans, candidate: "compat/discourse/lib/portable_ember_asset_graph.rb",
         candidate_sha256: Digest::SHA256.hexdigest(text),
         scope: "Pure manifest graph dependency only; not full EmberAssets or HTML/page acceptance",
         transformations: ["script_chunks/import_map take the caller's live manifest explicitly",
           "Build status, filesystem acquisition and lifecycle cache remain outside this pure dependency",
           "Original traversal, Set cycle suppression, entrypoint merge, naming and mapping retained"],
         captured_runtime_manifest: false, html_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_ember_asset_graph.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated source-derived pure EmberAssets graph dependency"
