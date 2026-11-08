# frozen_string_literal: true
# Shared source adaptation: statically expand the ACTUAL AMS0.8 declarations.
# The read algorithms come from the verified gem, never from captured JSON.
require "prism"
require "json"
require "digest"
require "fileutils"
root = File.expand_path("../..", __dir__)
reference = File.join(root, "discourse")
candidate = File.join(root, "fidelity/compat/discourse")
framework = File.join(root, "fidelity/source/framework/active_model_serializers-0.8.4/lib/active_model/serializer.rb")
source = File.binread(framework)
def serializer_nodes(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| serializer_nodes(child, result) }
  result
end
owner = serializer_nodes(Prism.parse(source).value).grep(Prism::ClassNode).find { |node| node.constant_path.slice == "Serializer" }
methods = owner.body.body.grep(Prism::DefNode)
roots = %i[root_name url_options meta_key include_meta as_json serializable_hash merge_association scope _serializable_hash perform_caching?]
selected = methods.select { |node| roots.include?(node.name) }
raise "AMS read roots changed" unless selected.map(&:name).sort == roots.sort
spans = selected.map { |node| {name: node.name, start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} }
# The instance side of the actual gem's class_attribute declarations. Defaults
# below are its declared nil/:objects values, not observed effective settings.
forwarders = %w[_root _embed _root_embed cache perform_caching].map do |name|
  "def #{name}\n    self.class.#{name}\n  end"
end
base = <<~RUBY
  # frozen_string_literal: true
  # AMS0.8.4 read algorithm with source declarations statically expanded.
  # Dynamic serializer mutation, scope aliases, cache activation and unknown
  # serializer classes are NOT admitted by this explicit read profile.
  class PortableSerializerRead
    attr_reader :object, :options
    def initialize(object, options = {})
      raise ArgumentError, "unsupported serializer scope alias" if options[:scope_name]
      raise ArgumentError, "unsupported authenticated serializer scope" if options[:scope] && options[:scope].user
      @object, @options = object, options
    end
    def self._root; nil; end
    def self._embed; :objects; end
    def self._root_embed; nil; end
    def self.cache; nil; end
    def self.perform_caching; nil; end
    #{forwarders.join("\n\n")}

    #{selected.map { |method|
      if method.name == :serializable_hash
        'def serializable_hash; raise ArgumentError, "unsupported activated serializer caching" if perform_caching?; @node = _serializable_hash; include_associations! if @object.present? && _embed; @node; end'
      else
        method.slice
      end
    }.join("\n\n")}
  end
RUBY
raise "invalid portable serializer read base" unless Prism.parse(base).success?
target = File.join(candidate, "lib/portable_serializer_read.rb")
FileUtils.mkdir_p(File.dirname(target))
File.binwrite(target, base)
manifest = {profile: "WIP shared AMS0.8 source declaration expansion; NOT request acceptance", framework_source: framework.delete_prefix(root + "/"),
  framework_sha256: Digest::SHA256.hexdigest(source), copied_read_methods: spans,
  declared_defaults_not_effective_values: true, captured_payload_as_input: false,
  constructor_change: "Preserve object/options initialization; nonnil scope_name explicitly refuses unsupported singleton alias generation",
  guarded_cache_change: "serializable_hash preserves the actual uncached algorithm; activated caching explicitly refuses instead of importing unrelated cache machinery",
  unsupported: %w[dynamic_serializer_mutation caching scope_name_alias unknown_serializer_classes],
  candidate_source_sha256: {"lib/portable_serializer_read.rb" => Digest::SHA256.hexdigest(base)},
  native_query_executed: false, json_request_accepted: false, full_query_accepted: false, page_accepted: false}
manifest_path = File.join(root, "fidelity/progressive/stage4")
FileUtils.mkdir_p(manifest_path)
File.write(File.join(manifest_path, "SERIALIZER_SOURCE_MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest)
