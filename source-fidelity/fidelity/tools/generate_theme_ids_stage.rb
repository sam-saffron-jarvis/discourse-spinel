# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], forced_synchronization: false, page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "Theme ID source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(source)
  source
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "Theme ID method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
theme = read.call('app/models/theme.rb')
ids = select.call(theme, :theme_ids).slice
get = select.call(theme, :get_set_cache).slice
cache = read.call('lib/distributed_cache.rb')
defer = select.call(cache, :defer_get_set).slice
native_defer = defer.sub('def defer_get_set(k, &block)', 'def defer_get_set_ids(k)').sub('value = block.call', 'value = yield')
native_defer = native_defer.sub('return self[k] if hash.key? k', "if hash.key? k\n      hit = self[k]\n      ThemeIdsRead.check_value(hit)\n      return ENV.fetch('FIDELITY_THEME_IDS_FAULT', '') == 'copied-warm' ? hit.dup : hit\n    end")
native_defer = native_defer.sub('    value = yield', "    value = yield\n    ThemeIdsRead.check_value(value)\n    CategoryCacheBootstrap.lease.note_theme_ids(k, value)")
native_defer = native_defer.sub('    raise TypeError if', "    ThemeIdsRead.check_key(k)\n    raise TypeError if")
File.write(File.join(build, 'theme_ids_cache_source.rb'), "module CategoryCacheApplication\nclass DistributedCache\n#{native_defer}\nend\nend\n")
native_get = get.sub('def self.get_set_cache(key, &blk)', 'def self.get_set_cache_ids(key)').sub('cache.defer_get_set(key, &blk)', 'cache.defer_get_set_ids(key) { yield }')
native_ids = ids.sub('get_set_cache "theme_ids"', 'get_set_cache_ids "theme_ids"').sub('Theme.pluck(:id)', 'ThemeIdsRead.acquire_ids')
File.write(File.join(build, 'theme_ids_source.rb'), "module RequestThemeIdsSource\ndef self.cache; CategoryCacheBootstrap.theme_compiler_cache; end\n#{native_get}\n#{native_ids}\nend\n")
# Raw original application methods are unchanged; independent raw cache/Scheduler
# bodies already execute on the same owned transport in the cumulative reference.
File.write(File.join(build, 'original_theme_ids_source.rb'), "module OriginalRequestThemeIdsSource\nTheme = ThemeIdsRead\ndef self.cache; ThemeIdsRead.original_cache; end\n#{get}\n#{ids}\nend\n")
manager = read.call('lib/stylesheet/manager.rb')
detail = select.call(manager, :color_scheme_stylesheet_details)
statements = detail.body.body.first(2).map(&:slice).join("\n")
raise 'stylesheet Theme membership cursor changed' unless statements.include?('Theme.theme_ids.include?(theme_id)')
File.write(File.join(build, 'theme_ids_stylesheet_source.rb'), "module ThemeIdsStylesheetPrefix\ndef acquire_color_theme_ids\n#{statements.gsub('Theme.theme_ids', 'ThemeIdsRead.source_ids')}\nThemeIdsRead.note_consumer(theme_id)\nraise HtmlRenderingBoundary, 'actual Theme ID Integer cache acquired; ColorScheme lookup/base acquisition pending'\nend\nend\n")
proof[:adaptations] = ['Actual theme_ids/get_set_cache/defer_get_set/pluck order, bare yield native block specialization only', 'Exact Integer Array guards and observation before actual defer_set; no sorting/casting/copying/freezing of production values', 'No new outer monitor, sleep, synchronization, synchronous scheduler mode, preload or publication fence', 'Warm identity/no-requery/no-enqueue verified at existing real cleanup drain, not forced production timing', 'Existing String/extra_js Array[Hash]/SVG admissions stay strict; exact theme_ids Array[Integer] wire registration only', 'Actual first two stylesheet detail statements consume source ID cache and real default theme, then refuse before unacquired ColorScheme collaborator']
File.write(File.join(build, 'theme-ids-source-proof.json'), JSON.pretty_generate(proof) + "\n")
