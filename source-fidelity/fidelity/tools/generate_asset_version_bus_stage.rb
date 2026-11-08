# frozen_string_literal: true
# Exact additional MessageBus API on the existing owned instance/backend.
require 'prism'
require 'json'
require 'digest'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
source, metadata = FidelitySourcePackage.member(root, 'message_bus-5.0.0', 'lib/message_bus.rb')
owner = Prism.parse(source).value.statements.body.find { |n| n.is_a?(Prism::ModuleNode) && n.constant_path.slice == 'MessageBus::Implementation' }
names = %i[backlog last_id last_message]
nodes = owner.body.body.grep(Prism::DefNode).select { |n| names.include?(n.name) }
raise 'asset-version bus method set changed' unless nodes.map(&:name).sort == names.sort
methods = nodes.map(&:slice).join("\n")
# This acquisition admits only the source asset-version channel, not arbitrary
# global backlog enumeration or subscription replay.
methods = methods.sub('def backlog(channel = nil, last_id = nil, site_id = nil)', 'def backlog(channel = nil, last_id = nil, site_id = nil); raise ArgumentError, "asset-version backlog requires channel" if channel.nil?')
File.write(File.join(build, 'asset_version_bus_source.rb'), "module CategoryCacheMessageBus::Implementation\n#{methods}\nend\n")
File.write(File.join(build, 'asset-version-bus-source-proof.json'), JSON.pretty_generate({framework: metadata, spans: nodes.map { |n| {name: n.name, start: n.location.start_offset, end: n.location.end_offset, sha256: Digest::SHA256.hexdigest(n.slice)} }, transformations: ['Exact original last_message/last_id/backlog, existing original Redis backend, Lua and codec', 'Unsupported nil-channel/global enumeration refuses; same owned single-site instance', 'Synchronous global asset-version publication has nil targets; deferred cache guards unchanged'], full_layout_completed: false}) + "\n")
