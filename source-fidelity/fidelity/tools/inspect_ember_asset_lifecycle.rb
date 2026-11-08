# frozen_string_literal: true
# Write-free ORIGINAL full-class lifecycle inspection, NOT request/page input.
require "pathname"
require "digest"
require "json"
require "open3"
require "set"
require "erb"
require "active_support"
require "active_support/current_attributes"
require "active_support/environment_inquirer"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
path = "lib/ember_assets.rb"
source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
raise "source lifecycle changed" unless status.success? && File.binread(File.join(root, "discourse", path)) == source.b
module Rails
  class << self; attr_accessor :root; end
  def self.env; ActiveSupport::EnvironmentInquirer.new(ENV.fetch("RAILS_ENV")); end
end
raise "unadmitted real asset environment" unless Rails.env.development?
Object.class_eval(source, "pinned original EmberAssets")
observations = []
["discourse", "fidelity/build/recovery24-frontend/source"].each do |relative|
  Rails.root = Pathname.new(File.join(root, relative))
  before = Thread.list.size
  begin
    EmberAssets.reset
    source_manifest = Rails.root.join("frontend/discourse/dist/manifest/manifest.json")
    initial = EmberAssets.request_cache
    begin
      imports = EmberAssets.import_map
      chunks = EmberAssets.script_chunks
      cache = EmberAssets.cache
      manifest = cache[:manifest]
      warm_imports = EmberAssets.import_map
      warm_chunks = EmberAssets.script_chunks
      raise "original request-cache lifecycle did not retain real results: #{[imports == warm_imports, chunks.equal?(warm_chunks), cache.equal?(EmberAssets.cache), manifest.equal?(EmberAssets.cache[:manifest]), cache.keys, EmberAssets.cache.keys].inspect}" unless imports == warm_imports && chunks.equal?(warm_chunks) && cache.equal?(EmberAssets.cache) && manifest.equal?(EmberAssets.cache[:manifest]) && cache.key?(:build_error)
      observations << {root: relative, initial_request_cache_nil: initial.nil?, original_build_error: false,
        manifest_sha256: Digest::SHA256.file(source_manifest).hexdigest, import_entries: imports.size, chunk_entries: chunks.size,
        source_acquired: true, genuine_warm_hits: true, imports_return_identity: imports.equal?(warm_imports), retained_manifest_identity: true, html_accepted: false}
    rescue EmberAssets::BuildError => error
      raise unless !File.exist?(source_manifest) && error.details["status"] == "missing"
      observations << {root: relative, original_build_error: true, error: error.message, details: error.details,
        missing_manifest_observed: true, html_accepted: false}
    end
  ensure
    EmberAssets.reset
    raise "original request-cache state leaked" unless EmberAssets.request_cache.nil?
    raise "original asset lifecycle thread leaked" unless Thread.list.size == before
  end
end
puts JSON.pretty_generate({purpose: "ORIGINAL full EmberAssets readonly lifecycle inspection ONLY; never production payload", pin: pin,
  source_sha256: Digest::SHA256.hexdigest(source), observations: observations,
  no_watch_build_process_pg_or_publication_dispatched: true, page_accepted: false})
