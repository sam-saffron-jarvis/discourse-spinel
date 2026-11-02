# frozen_string_literal: true
# Verification-only original Emoji.exists? with a local cache TRANSPORT adapter.
# Original lookup/normalization/standard/aliases execute; no cached source result
# is fabricated and no deferred Redis publication is scheduled by these probes.
require "json"
abort "task PG required" unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"
abort "task Valkey required" unless ENV["REDIS_URL"] == "redis://127.0.0.1:6399/0"
root = File.expand_path("..", __dir__)
fixture = JSON.parse(File.read(File.join(root, "build/emoji-existence-native.json")))
class EmojiExistenceLocalCache
  def initialize = @values = {}
  def defer_get_set(key)
    @values.fetch(key) { @values[key] = yield }
  end
end
ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  standard = Emoji.load_standard
  custom = Emoji.load_custom
  raise "custom/plugin emoji not extracted" unless custom.empty?
  global_cache = EmojiExistenceLocalCache.new
  site_cache = EmojiExistenceLocalCache.new
  Emoji.define_singleton_method(:standard) { standard }
  Emoji.define_singleton_method(:custom) { custom }
  Emoji.define_singleton_method(:global_emoji_cache) { global_cache }
  Emoji.define_singleton_method(:site_emoji_cache) { site_cache }
  fixture.fetch("probes").each do |probe|
    # Original deferred distributed caches key only the base name, not tone.
    # Use a fresh local transport for each probe to measure the actual cold
    # lookup predicate, not order-dependent prior cache entries.
    Emoji.define_singleton_method(:global_emoji_cache) { global_cache }
    Emoji.define_singleton_method(:site_emoji_cache) { site_cache }
    global_cache = EmojiExistenceLocalCache.new
    site_cache = EmojiExistenceLocalCache.new
    result = begin
      Emoji.exists?(probe["name"])
    rescue NoMethodError
      "invalid"
    end
    raise "source Emoji.exists? mismatch: #{probe.inspect} => #{result.inspect}" unless probe["exists"] == result
  end
end
puts JSON.generate({ "read_only" => true, "synthetic_probes" => true,
  "original_source" => "Emoji.exists?/[]/normalize_name/find_emoji/load_standard/resolve_alias",
  "cache_transport" => "test-only local cache instead of deferred Redis publication; original lookup block executes",
  "probe_count" => fixture.fetch("probes").length })
