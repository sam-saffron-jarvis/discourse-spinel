# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
read = lambda do |path|
  value, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "component source changed #{path}" unless status.success? && value.b == File.binread(File.join(root, 'discourse', path))
  value
end
asset = read.call('lib/asset_processor.rb')
version = Prism.parse(asset).value.statements.body.grep(Prism::ClassNode).first.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :BASE_COMPILER_VERSION }
raise 'source asset compiler declaration missing' unless version
key = "theme:compiler:#{version.value.slice}"
File.write(File.join(build, 'theme_ids_component_binding.rb'), <<~RUBY)
  module CategoryCacheBootstrap
    def self.theme_compiler_cache
      return acquired_theme_compiler_cache unless acquired_theme_compiler_cache.nil?
      lease.theme_cache_key = #{key.dump}
      self.acquired_theme_compiler_cache = CategoryCacheApplication::DistributedCache.new(lease.theme_cache_key, manager: manager)
      raise 'Theme IDs component subscription missing' unless bus.backend_instance.subscribed && manager.subscribers.size == 2
      acquired_theme_compiler_cache
    end
  end
RUBY
File.write(File.join(build, 'theme_ids_component_original_binding.rb'), <<~RUBY)
  require_relative 'original_theme_ids_source'
  module ThemeIdsRead
    def self.acquire_ids; observe_pluck(::Theme.pluck(:id)); end
    def self.pluck(column)
      raise ArgumentError, 'Theme IDs pluck column' unless column == :id
      acquire_ids
    end
    def self.original_cache; CategoryCacheBootstrap.theme_compiler_cache; end
    def self.source_ids; OriginalRequestThemeIdsSource.theme_ids; end
  end
  class ObservedOriginalCategoryCache
    alias_method :component_raw_defer_get_set, :defer_get_set
    def defer_get_set(key)
      return component_raw_defer_get_set(key) { yield } unless key == 'theme_ids'
      component_raw_defer_get_set(key) do
        value = yield
        CategoryCacheBootstrap.lease.note_theme_ids(key, value)
        value
      end
    end
    def defer_get_set_ids(key); defer_get_set(key) { yield }; end
  end
  module CategoryCacheBootstrap
    def self.theme_compiler_cache
      return acquired_theme_compiler_cache unless acquired_theme_compiler_cache.nil?
      lease.theme_cache_key = #{key.dump}
      self.acquired_theme_compiler_cache = ObservedOriginalCategoryCache.new(lease.theme_cache_key, manager: manager)
      raise 'Theme IDs component original subscription missing' unless bus.backend_instance.subscribed && manager.subscribers.size == 2
      acquired_theme_compiler_cache
    end
  end
RUBY
File.write(File.join(build, 'theme-ids-component-source-proof.json'), JSON.pretty_generate({pin: pin, cache_key_declaration: version.slice, source_sha256: Digest::SHA256.hexdigest(asset), actual_theme_cache_source_sha256: Digest::SHA256.hexdigest(read.call('app/models/theme.rb')), component_only: true, page_accepted: false}) + "\n")
