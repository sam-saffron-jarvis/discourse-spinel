# frozen_string_literal: true
# Acquire only source needed by Category#url; no full application initializer.
require "prism"
require "json"
require "digest"
require "open3"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
build = ARGV.fetch(0)
app = ARGV.fetch(1)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, application: {}, packages: [], spans: [], transformations: []}
read = lambda do |path|
  bytes, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "changed application source #{path}" unless status.success? && File.binread(File.join(root, "discourse", path)) == bytes.b
  proof[:application][path] = Digest::SHA256.hexdigest(bytes)
  bytes
end
package = lambda do |member|
  bytes, metadata = FidelitySourcePackage.member(root, "message_bus-5.0.0", member)
  proof[:packages] << metadata
  bytes
end
methods = lambda do |text, names, label|
  found = []
  walk = lambda do |node|
    if node.is_a?(Prism::DefNode) && names.include?(node.name)
      found << node
    else
      node.compact_child_nodes.each { |child| walk.call(child) }
    end
  end
  walk.call(Prism.parse(text).value)
  raise "source method set changed #{label}" unless found.map(&:name).sort == names.sort
  found.each { |n| proof[:spans] << {source: label, name: n.name, start_byte: n.location.start_offset, end_byte: n.location.end_offset, sha256: Digest::SHA256.hexdigest(n.slice)} }
  found.map(&:slice).join("\n")
end
bus = package.call("lib/message_bus.rb")
implementation = Prism.parse(bus).value.statements.body.find { |n| n.is_a?(Prism::ModuleNode) && n.constant_path.slice == "MessageBus::Implementation" }
raise "bus owner changed" unless implementation
names = %i[initialize logger logger= configure site_id_lookup backend_instance backend redis_config redis_config= publish subscribe subscribe_impl ensure_subscriber_thread new_subscriber_thread global_subscribe_thread multi_each encode_channel_name decode_channel_name decode_message! global? destroy timer keepalive_interval transport_codec]
impl = methods.call(implementation.slice, names, "message_bus/Implementation")
# Native namespace only: same source is used by SAME-lowered CRuby. No core bus
# is modified and no default global backend can be selected by the adapter.
# DistributedCache.Manager always subscribes with the source default -1. Other
# replay profiles are outside this single-cache capability, not silently omitted.
impl_tree = Prism.parse(impl).value
subscribe_impl = impl_tree.statements.body.find { |n| n.is_a?(Prism::DefNode) && n.name == :subscribe_impl }
replay_if = subscribe_impl.body.body.find { |n| n.is_a?(Prism::IfNode) && n.predicate.slice == "last_id >= 0" }
raise "source subscription replay branch changed" unless replay_if
impl[replay_if.location.start_offset, replay_if.location.length] = 'raise ArgumentError, "unsupported category cache subscription replay profile" unless last_id == -1'
original_subscribe_impl = methods.call(implementation.slice, [:subscribe_impl], "message_bus/original_subscription")
File.write(File.join(build, "original_category_cache_subscription.rb"), "module CategoryCacheMessageBus::Implementation\n#{original_subscribe_impl.gsub(/\bMessageBus\b/, 'CategoryCacheMessageBus')}\nend\n")
registry_lines = "@subscriptions[site_id] ||= {}\n    @subscriptions[site_id][channel] ||= []\n    @subscriptions[site_id][channel] << blk"
raise "source registration changed" unless impl.include?(registry_lines)
impl = impl.gsub("@subscriptions ||= {}", "@subscriptions ||= CategoryCacheSubscriptions.new").sub(registry_lines, "@subscriptions.register(channel, site_id, blk)")
impl = impl.sub(/require ['"]logger['"]/, "").sub('require "message_bus/backends/#{backend}"', '')
base = package.call("lib/message_bus/backends/base.rb")
redis = package.call("lib/message_bus/backends/redis.rb")
redis = redis.sub('require "redis"', '')
redis = redis.gsub("::Redis", "::CategoryCacheRedisClient")
redis = redis.sub("      private\n", "      def owned_fixture_client; pub_redis; end\n      private\n")
cache = package.call("lib/message_bus/distributed_cache.rb")
cache = cache.sub("require 'weakref'", "").sub('    def identity', '    def category_values; hash; end\n    def identity'.gsub('\n', "\n"))
# Category's singleton cache is strongly rooted for the entire scope. Preserve
# real registration and callback dispatch; unknown/collectable caches refuse.
cache = cache.sub('@message_bus.subscribe(CHANNEL_NAME)', "bus = @message_bus\n          raise ArgumentError, 'unbound concrete cache bus' unless bus.is_a?(CategoryCacheMessageBus::Instance)\n          bus.subscribe(CHANNEL_NAME)")
cache = cache.sub('    @data = {}', '    @data = {}; @category_data_monitor = Monitor.new')
cache = cache.sub("      @manager.set(self, k, v)\n      hash[k] = v", "      @category_data_monitor.synchronize do\n        @manager.set(self, k, v)\n        hash[k] = v\n      end")
cache = cache.sub('def ensure_subscribe!', 'def ensure_subscribe!; return if ENV.fetch("FIDELITY_CACHE_FAULT", "") == "missing-subscription"')
cache = cache.sub('def set(hash, key, value)', 'def set(hash, key, value); return if ENV.fetch("FIDELITY_COMPILER_FAULT", "") == "missing-compiler-publication" && !CategoryCacheBootstrap.lease.theme_cache_key.nil? && hash.key == CategoryCacheBootstrap.lease.theme_cache_key')
cache = cache.sub('def set(hash, key, value)', 'def set(hash, key, value); return if ENV.fetch("FIDELITY_LAYOUT_FAULT", "") == "missing-color-publication" && hash.key == "scheme_hex_for_name"')
cache = cache.sub('def set(hash, key, value)', 'def set(hash, key, value); return if ENV.fetch("FIDELITY_CACHE_FAULT", "") == "missing-publication"')
cache = cache.sub('def []=(k, v)', 'def []=(k, v); raise "negative layout color assignment exception" if ENV.fetch("FIDELITY_LAYOUT_FAULT", "") == "color-job-exception" && key == "scheme_hex_for_name"')
cache = cache.sub('def []=(k, v)', 'def []=(k, v); raise "negative deferred assignment exception" if ENV.fetch("FIDELITY_CACHE_FAULT", "") == "job-exception"')
cache = cache.sub("        @manager.set(self, k, v)\n        hash[k] = v", "        CategoryCacheBootstrap.lease.assignment_begin(k)\n        if ENV.fetch(\"FIDELITY_CACHE_FAULT\", \"\") == \"wrong-update-order\"\n          hash[k] = v\n          CategoryCacheBootstrap.lease.assignment_updated(k)\n        end\n        @manager.set(self, k, v)\n        hash[k] = v\n        CategoryCacheBootstrap.lease.assignment_updated(k)")
cache = cache.sub('def process_message(message)', 'def process_message(message); CategoryCacheBootstrap.lease.event("manager_process_message")')
cache = cache.gsub("WeakRef.new(hash)", "CategoryCacheRootRef.new(hash)").gsub("WeakRef::RefError", "CategoryCacheRootRef::RefError")
message = package.call("lib/message_bus/message.rb")
timer = package.call("lib/message_bus/timer_thread.rb")
codec = package.call("lib/message_bus/codec/json.rb")
# Avoid lazy autoload of unrelated codecs; the original default is Codec::Json.
codec = "module MessageBus; module Codec; class Base; end; end; end\n" + codec
framework = <<~RUBY
require "json"
require "logger"
require "monitor"
require "base64"
require "securerandom"
module MessageBus
  BACKENDS = {}
  class InvalidMessage < StandardError; end
  class InvalidMessageTarget < InvalidMessage; end
  class BusDestroyed < StandardError; end
  module Implementation
    class Synchronizer
      include MonitorMixin
    end
    ENCODE_SITE_TOKEN = "$|$"
    MIN_KEEPALIVE = 20
    #{impl}
  end
  class Instance
    include Implementation
  end
  extend Implementation
  initialize
end
#{message}
#{timer}
#{codec}
#{base}
#{redis}
#{cache}
RUBY
framework = framework.gsub(/\bMessageBus\b/, "CategoryCacheMessageBus")
File.write(File.join(build, "category_cache_bus_source.rb"), framework)
work = read.call("lib/work_queue.rb")
work = work.sub('@elements = Hash.new { |h, k| h[k] = blk.call }', '@factory = blk; @elements = {}').sub('@elements[key].push(task, force: force)', '@elements[key] ||= @factory.call; @elements[key].push(task, force: force)')
work = work.sub('key = task[@key]', 'key = task[@key]; raise ArgumentError, "unsupported non-nil category deferred user" if @key == :user && !key.nil?; key = "category-nil-user" if key.nil?')
defer_full = read.call("lib/scheduler/defer.rb")
deferrable_node = Prism.parse(defer_full).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ModuleNode).first
constants = deferrable_node.body.body.grep(Prism::ConstantWriteNode).map(&:slice).join("\n")
defer_methods = methods.call(defer_full, %i[initialize later stop! start_thread do_work stats length], "lib/scheduler/defer.rb")
defer = "module Scheduler\nmodule Deferrable\n#{constants}\nattr_reader :async\n#{defer_methods}\nend\nclass Defer\nextend Deferrable\ninitialize\nend\nend\n"
defer = defer.gsub("MessageBus::", "CategoryCacheMessageBus::").sub('Thread.current.abort_on_exception = true if Rails.env.test?', 'raise ArgumentError, "unsupported deferred test mode" if Rails.env.test?')
# Stats has only the one accepted Category cache descriptor; no general LRU use.
defer = defer.sub("LruRedux::ThreadSafeCache.new(STATS_CACHE_SIZE)", "CategoryCacheStats.new(STATS_CACHE_SIZE)")
distributed_full = read.call("lib/distributed_cache.rb")
distributed = "class DistributedCache < MessageBus::DistributedCache\n" + methods.call(distributed_full, %i[initialize defer_set defer_get_set], "lib/distributed_cache.rb") + "\nend\n"
distributed = distributed.sub("MessageBus::DistributedCache", "CategoryCacheMessageBus::DistributedCache")
# The acquired URL always supplies this block. Bare yield is the same Ruby
# computation without boxing a pure synchronous block through an untyped slot.
distributed = distributed.sub('def defer_set(k, v)', 'def defer_set(k, v); return self[k] = v if ENV.fetch("FIDELITY_CACHE_FAULT", "") == "missing-defer"')
distributed = distributed.sub('def defer_get_set(k, &block)', 'def defer_get_set(k)').sub('value = block.call', 'value = yield')
distributed = distributed.sub('def defer_get_set(k)', 'def defer_get_set(k); @category_data_monitor.synchronize do').sub("    value\n  end", "    value\n  end; end")
raise "invalid live cache projection" unless Prism.parse(distributed).success? && Prism.parse(defer).success? && Prism.parse(work).success?
File.write(File.join(build, "category_cache_application_source.rb"), "module CategoryCacheApplication\n#{work}\n#{defer}\n#{distributed}\nend\n")
File.write(File.join(build, "original_category_cache_application_source.rb"), "module OriginalCategoryCacheApplication\n#{read.call('lib/work_queue.rb')}\n#{read.call('lib/scheduler/defer.rb')}\n#{read.call('lib/distributed_cache.rb')}\nend\n")
# Record original initializer/configuration and exact Category URL/slug spans.
%w[app/models/global_setting.rb config/initializers/004-message_bus.rb config/discourse_defaults.conf].each do |p|
  # Actual initializer filename is checked, never guessed silently.
  read.call(p)
end
category = read.call("app/models/category.rb")
url_methods = methods.call(category, %i[url slug_path slug_for_url], "app/models/category.rb")
File.write(File.join(build, "category_cache_category_methods.rb"), "module CategoryCacheCategoryMethods\n#{url_methods}\nend\n")
native_category = url_methods.sub('@@url_cache.defer_get_set', "cache = CategoryCacheBootstrap.cache\n    raise ArgumentError, 'unbound concrete category cache' unless cache.is_a?(CategoryCacheApplication::DistributedCache)\n    cache.defer_get_set").gsub("parent_category_id.present?", "ActiveSupport.present?(parent_category_id)").gsub("slug.presence", "ActiveSupport.presence(slug)")
raise "invalid concrete category source" unless Prism.parse(native_category).success?
category_path = File.join(app, "app/models/category.rb")
File.write(category_path, File.read(category_path).sub(/end\s*\z/) { "belongs_to :parent_category, class_name: \"Category\"\nend\n" })
File.write(File.join(build, "native_category_cache_category_methods.rb"), "module NativeCategoryCacheCategoryMethods\n#{native_category}\nend\nclass Category\ninclude NativeCategoryCacheCategoryMethods\nend\n")
null_bytes, null_proof = FidelitySourcePackage.member(root, "rails_multisite-9.0.0", "lib/rails_multisite/connection_management/null_instance.rb")
proof[:packages] << null_proof
null_methods = methods.call(null_bytes, %i[current_db has_db? with_connection], "RailsMultisite::NullInstance")
%i[current_db has_db? with_connection].each { |name| null_methods = null_methods.sub("def #{name}", "def self.#{name}") }
default_bytes, default_proof = FidelitySourcePackage.member(root, "rails_multisite-9.0.0", "lib/rails_multisite/connection_management.rb")
proof[:packages] << default_proof
default_declaration = default_bytes.lines.find { |line| line.strip.start_with?('DEFAULT = ') }.strip
# Only DEFAULT single-site is admitted. Bind these unchanged original bodies to
# each isolated source namespace; no configured multisite bootstrap is executed.
null_bindings = "module RailsMultisite\nclass UnknownSiteError < StandardError; end\nclass ConnectionManagement\n#{default_declaration}\n#{null_methods}\nend\nend\n"
File.write(File.join(build, "category_cache_single_site.rb"), "module CategoryCacheApplication\n#{null_bindings}\nend\nmodule OriginalCategoryCacheApplication\n#{null_bindings}\nend\n")
proof[:transformations] = ["namespace MessageBus -> CategoryCacheMessageBus", "Redis transport -> mandatory guarded RESP adapter; source backend/Lua retained", "strong root reference only for category_url singleton lifetime", "single accepted descriptor stats storage; actual WorkQueue/Scheduler/Timer methods retained", "source-default subscription last_id=-1 guarded; inapplicable replay branch pruned", "typed ActiveSupport.present?/presence lowering for nullable parent ID and slug", "single-category subscription topology uses typed registry rather than nil Hash key; reference retains original Hash", "nil user queue key represented internally by guarded sentinel for source-only nil-user profile", "synchronous URL computation block.call -> bare yield (real deferred block unchanged)", "only live Scheduler methods selected; uncalled capture_later/test mutators excluded", "local hash operations synchronized across native parallel workers; publication-before-local-assignment retained", "development-only profile rejects unreachable Thread.abort_on_exception test branch", "FairQueue lazy factory retained explicitly on its owner rather than nested default-Proc capture; same first-miss invocation"]
proof[:source_bus_sha256] = Digest::SHA256.hexdigest(framework)
proof[:original_full_rails_html_invoked] = false
File.write(File.join(build, "category-cache-source-proof.json"), JSON.pretty_generate(proof) + "\n")
