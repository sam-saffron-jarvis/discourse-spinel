# frozen_string_literal: true
# Bounded source projection: real development request lifecycle, not a watcher.
require "prism"
require "json"
require "digest"
require "open3"
root = File.expand_path("../..", __dir__)
build = ARGV.fetch(0)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
path = "lib/ember_assets.rb"
source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
raise "EmberAssets source changed" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
names = %i[dist_dir script_chunks import_map logical_name deep_imports_for build_error wait_for_build read_build_status pid_alive? raise_if_build_error! read_manifest! plain_error cache clear_cache!]
spans = []
methods = names.map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == name }
  raise "missing original method #{name}" unless node
  spans << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  text = node.slice.sub("def self.", "def ")
  text = text.gsub('Rails.root.join("frontend/discourse/dist")', 'File.join(@root, "frontend/discourse/dist")')
  text = text.gsub("Rails.env.local?", "@environment.local?").gsub("Rails.env.development?", "@environment.development?")
  %w[manifest import_map script_chunks build_error].each do |field|
    text = text.gsub("cache[:#{field}]", "cache.#{field}")
  end
  text = text.gsub("cache.key?(:build_error)", "cache.build_error_read")
  text = text.sub("cache.build_error = wait_for_build", "value = wait_for_build\n    cache.build_error = value\n    cache.build_error_read = true\n    value")
  text = text.sub("self.request_cache ||= {}", "@request_cache ||= RequestEmberCache.new")
  text = text.sub("@production_cache ||= {}", "raise ArgumentError, 'unsupported non-development EmberAssets cache profile'")
  text = text.sub("self.request_cache = nil", "@request_cache = nil").sub("    @production_cache = nil", "")
  if name == :import_map
    original = <<~'SOURCE'.chomp
      cache.import_map ||= (
            read_manifest!(exception: true)&.dig("importMap") || {}
          ).to_h { |stable, real| [logical_name(stable), logical_name(real)] }
    SOURCE
    replacement = <<~'SOURCE'.chomp
      return cache.import_map unless cache.import_map.nil?
          mapped = {}
          (read_manifest!(exception: true)&.dig("importMap") || {}).each do |stable, real|
            mapped[logical_name(stable)] = logical_name(real)
          end
          cache.import_map = mapped
    SOURCE
    raise 'original import-map formation changed' unless text.include?(original)
    text = text.sub(original, replacement)
  end
  text = text.sub("def wait_for_build\n", "def wait_for_build\n    reject_live_build_profile!\n")
  text
end
# Explicit field types preserve source Hash slot identity, without widening a
# manifest Hash to the incompatible map/chunk/error result types.
cache = <<~RUBY
  class RequestEmberCache
    attr_accessor :manifest, :import_map, :script_chunks, :build_error, :build_error_read
    def initialize
      @manifest = nil
      @import_map = nil
      @script_chunks = nil
      @build_error = nil
      @build_error_read = false
    end
  end
  class RequestAssetEnvironment
    def initialize(name)
      raise ArgumentError, 'unsupported asset environment' unless name == 'development'
      @name = name
    end
    def development?; @name == 'development'; end
    def local?; @name == 'development' || @name == 'test'; end
  end
  class RequestEmberAssets
    class BuildError < StandardError
      attr_reader :details
      def initialize(details)
        @details = details
        super(details.dig("error", "message") || "Frontend build failed")
      end
    end
    BUILD_WAIT_TIMEOUT = 20.0
    BUILD_POLL_INTERVAL = 0.05
    attr_reader :request_cache
    def initialize(root, environment)
      @root = root
      @environment = environment
      @request_cache = nil
    end
    def reset; clear_cache!; end
    def watch!; raise ArgumentError, 'unsupported live asset watcher profile'; end
    def reject_live_build_profile!
      data = read_build_status
      return if data.nil?
      raise ArgumentError, 'unsupported live asset build profile' if data['status'] == 'building' || (data['pid'] && pid_alive?(data['pid']))
    end
    #{methods.join("\n\n")}
  end
RUBY
raise "invalid asset projection" unless Prism.parse(cache).success?
File.write(File.join(build, "request_ember_assets.rb"), "# GENERATED source-backed development lifecycle. See source proof.\nrequire 'json'\nrequire 'set'\nrequire 'erb'\n#{cache}")
File.write(File.join(build, "request_ember_assets.rbs"), <<~RBS)
  class RequestEmberCache
    attr_accessor manifest: Hash[String, untyped]?
    attr_accessor import_map: Hash[String, String]?
    attr_accessor script_chunks: Hash[String, Array[String]]?
    attr_accessor build_error: Hash[String, untyped]?
    attr_accessor build_error_read: bool
  end
  class RequestEmberAssets
    attr_reader request_cache: RequestEmberCache?
    def initialize: (String root, RequestAssetEnvironment environment) -> void
    def read_manifest!: (exception: bool) -> Hash[String, untyped]?
    def read_build_status: () -> Hash[String, untyped]?
    def build_error: () -> Hash[String, untyped]?
    def wait_for_build: () -> Hash[String, untyped]?
    def import_map: () -> Hash[String, String]
    def script_chunks: (?exception: bool) -> Hash[String, Array[String]]
    def logical_name: (String filename) -> String
    def deep_imports_for: (chunk_filename: String, chunks: Hash[String, untyped], ?seen: Set[String]) -> Array[String]
    def cache: () -> RequestEmberCache
    def plain_error: (String text) -> Hash[String, String]
    def pid_alive?: (untyped pid) -> bool
  end
RBS
# Full original class and real AS context, not the candidate's typed cache.
original = <<~RUBY
  require 'pathname'
  require 'active_support'
  require 'active_support/current_attributes'
  require 'active_support/environment_inquirer'
  module OriginalAssetLifecycle
    module Rails
      class << self; attr_accessor :root; end
      def self.env; ActiveSupport::EnvironmentInquirer.new(ENV.fetch('RAILS_ENV')); end
    end
    #{source}
  end
  class OriginalRequestEmberAssets
    def initialize(root, environment)
      OriginalAssetLifecycle::Rails.root = Pathname.new(root)
      @source = OriginalAssetLifecycle::EmberAssets
      @source.reset
    end
    def request_cache; @source.request_cache; end
    def cache; @source.cache; end
    def import_map; reject_live_build_profile!; @source.import_map; end
    def script_chunks(exception: true); reject_live_build_profile! if exception; @source.script_chunks(exception: exception); end
    def read_manifest!(exception:); @source.read_manifest!(exception: exception); end
    def reset; @source.reset; end
    def clear_cache!; @source.clear_cache!; end
    def watch!; raise ArgumentError, 'unsupported live asset watcher profile'; end
    def reject_live_build_profile!
      return if @source.cache.key?(:build_error)
      data = @source.read_build_status
      return if data.nil?
      raise ArgumentError, 'unsupported live asset build profile' if data['status'] == 'building' || (data['pid'] && @source.pid_alive?(data['pid']))
    end
  end
RUBY
File.write(File.join(build, "original_request_ember_assets.rb"), original)
File.write(File.join(build, "original_request_asset_boot.rb"), <<~'RUBY')
  # Reference platform bootstrap BEFORE the lowered runtime reopens AS/I18n.
  # Retain the actual inherited reset implementation on the original subclass;
  # the lowered registry's abstract base reset must not replace the reference.
  require 'propshaft'
  require 'action_view/helpers/asset_url_helper'
  require_relative 'original_request_ember_assets'
  OriginalAssetLifecycle::EmberAssets.define_method(:reset, ActiveSupport::CurrentAttributes.instance_method(:reset))
RUBY
File.write(File.join(build, "ember-lifecycle-source-proof.json"), JSON.pretty_generate({pin: pin, source: path, source_sha256: Digest::SHA256.hexdigest(source), spans: spans,
  candidate_sha256: Digest::SHA256.file(File.join(build, "request_ember_assets.rb")).hexdigest, transformations: ["Source class methods bound to one explicitly owned request context", "CurrentAttributes request Hash slots specialized to typed fields; reset destroys the context", "Actual environment development/local decisions; no forced test mode", "Live builder/watcher explicitly refused before wait/watch dispatch"], html_accepted: false}) + "\n")
