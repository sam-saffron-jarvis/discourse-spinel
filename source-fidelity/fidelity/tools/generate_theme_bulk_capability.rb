# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:lib/distributed_cache.rb")
raise 'bulk cache source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/lib/distributed_cache.rb'))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :defer_get_set_bulk }
raise 'source bulk method missing' unless node
native = node.slice.sub('def defer_get_set_bulk(ks, key_blk, &blk)', 'def defer_get_set_fields(ks, key_blk)')
native = native.sub('missing_keys.present?', 'ActiveSupport.present?(missing_keys)').sub('blk.call(missing_keys.freeze)', 'yield missing_keys.freeze')
anchor = 'Scheduler::Defer.later("#{@key}_bulk_set") do'
raise 'bulk deferred publication source anchor changed' unless native.scan(anchor).size == 1
native = native.sub(anchor, <<~'SOURCE'.strip)
  missing_hash.each { |key, value| CategoryCacheBootstrap.lease.note_theme_field_value(key_blk.call(key), value) }
      CategoryCacheBootstrap.lease.note_bulk_enqueue(missing_hash.size)
      Scheduler::Defer.later("#{@key}_bulk_set") do
SOURCE
# Existing source cache is used from native parallel workers. The same acquired
# monitor already protects setter/publication ordering and other typed getters.
native = native.sub('def defer_get_set_fields(ks, key_blk)', 'def defer_get_set_fields(ks, key_blk); @category_data_monitor.synchronize do')
native += "\nend"
File.write(File.join(build, 'theme_bulk_cache_source.rb'), <<~RUBY)
  module CategoryCacheApplication
    class DistributedCache
      #{native}
      def theme_field_present?(key)
        @category_data_monitor.synchronize { hash.key?(key) }
      end
      def theme_field_hit(key)
        raise 'Theme field cache key outside lease' unless CategoryCacheBootstrap.lease.theme_field_key?(key)
        value = hash.fetch(key)
        raise TypeError, 'Theme field cache value type' unless value.nil? || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
        value
      end
    end
  end
RUBY
raise 'invalid bulk projection' unless Prism.parse_file(File.join(build, 'theme_bulk_cache_source.rb')).success?
File.write(File.join(build, 'theme-bulk-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), span: {start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}, transformations: ['Separate typed field bulk entrypoint on same original cache; original String/asset Array contracts unchanged', 'Original synchronous computation block.call -> yield, actual deferred lambda remains source', 'Native acquired data monitor serializes source read/write access', 'Computed field values registered only after real source block returns, before original scheduling; no provided hit'], page_accepted: false}) + "\n")
