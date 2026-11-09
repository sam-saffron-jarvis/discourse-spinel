# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:app/models/theme.rb")
raise 'transform cache source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/app/models/theme.rb'))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
names = %i[get_set_cache parent_theme_ids is_parent_theme? components_for transform_ids]
nodes = names.map do |name|
  found = owner.body.body.grep(Prism::DefNode).select { |n| n.name == name && n.receiver }
  raise "ambiguous transform cache method #{name}" unless found.size == 1
  found.first
end
raw = nodes.map(&:slice).join("\n")
native = raw.sub('def self.get_set_cache(key, &blk)', 'def self.get_set_cache_ids(key)').sub('cache.defer_get_set(key, &blk)', 'cache.defer_get_set_ids(key) { yield }')
native = native.gsub('get_set_cache "', 'get_set_cache_ids "').sub('id.blank?', 'ActiveSupport.blank?(id)').sub('.select { |t| !t.supported? || !t.enabled? }', '.filter { |t| !t.supported? || !t.enabled? }')
File.write(File.join(build, 'theme_transform_cache_source.rb'), "module RequestThemeTransformSource\ndef self.cache; CategoryCacheBootstrap.theme_compiler_cache; end\n#{native}\nend\n")
File.write(File.join(build, 'original_theme_transform_cache_source.rb'), "module OriginalTransformPrimitives\nrefine Object do\ndef blank?; ::ActiveSupport.blank?(self); end\nend\nend\nmodule OriginalRequestThemeTransformSource\nusing OriginalTransformPrimitives\ndef self.cache; CategoryCacheBootstrap.theme_compiler_cache; end\n#{raw}\nend\n")
File.write(File.join(build, 'theme-transform-cache-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), spans: nodes.map { |n| {name: n.name, start: n.location.start_offset, end: n.location.end_offset, sha256: Digest::SHA256.hexdigest(n.slice)} }, adaptations: ['Complete source parent_theme_ids/components_for/is_parent_theme?/transform_ids/get_set_cache, no bare ORM cache substitution', 'Existing typed Integer Array defer API, bare yield native binding and ordinary blank?/Enumerable select primitive lowering', 'Only three required exact keys for actual current theme ID; separately registered real Marshal bytes per key', 'No new locks/fences/waits/scheduler mode/seeds; cold PG source and deferred publication/warm identity use existing fixture lifecycle'], page_accepted: false}) + "\n")
