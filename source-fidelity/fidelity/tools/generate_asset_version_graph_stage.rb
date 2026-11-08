# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:lib/discourse.rb")
raise 'asset version source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/lib/discourse.rb'))
nodes = []
visit = lambda do |node|
  nodes << node if node.is_a?(Prism::DefNode) && node.name == :assets_digest
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(source).value)
raise 'asset version method ambiguous' unless nodes.size == 1
node = nodes.first
native = node.slice
anchor = "Rails\n              .application\n              .assets\n              .load_path\n              .assets"
raise 'asset version load_path receiver changed' unless native.include?(anchor)
native = native.sub(anchor, 'AssetVersionGraphBootstrap.assets')
observe = "channel = \"/global/asset-version\""
raise 'asset version channel source changed' unless native.include?(observe)
native = native.sub(observe, 'AssetVersionGraphBootstrap.note_digest(digest); ' + observe)
native = native.gsub('MessageBus.', 'AssetVersionGraphBootstrap.')
File.write(File.join(build, 'asset_version_graph_source.rb'), <<~RUBY)
  module ActionView
    class SourceAssetLoadPath
      def assets; assets_by_path.values; end
    end
  end
  module RequestAssetVersionSource
    #{native}
  end
RUBY
original = node.slice.sub(observe, 'AssetVersionGraphBootstrap.note_digest(digest); ' + observe)
File.write(File.join(build, 'original_asset_version_graph_source.rb'), <<~RUBY)
  class OriginalAssetVersionAssembly
    def assets; self; end
    def load_path; AssetVersionGraphBootstrap.verified_load_path; end
  end
  module OriginalAssetVersionSource
    module Rails
      def self.application; OriginalAssetVersionAssembly.new; end
    end
    MessageBus = AssetVersionGraphBootstrap
    #{original}
  end
RUBY
_, metadata = FidelitySourcePackage.member(root, 'propshaft-1.3.2', 'lib/propshaft/load_path.rb')
File.write(File.join(build, 'asset-version-graph-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), span: {start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}, framework: [metadata], transformations: ['Exact original assets_digest graph/digested-path/MD5/sort/join before MessageBus acquisition', 'Same explicitly owned provenance-verified serving load_path, not absent original root or supplied graph', 'Every enumerated member verified before reading; source LoadPath.assets values protocol bound exactly', 'Original full assets_digest method runs actual Propshaft load_path via explicit application collaborator', 'MessageBus last_message refuses before unacquired owned cache lifecycle; no fake digest return or memo hit'], page_accepted: false}) + "\n")
