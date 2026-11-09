# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG bundle source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(source)
  source
end
source = read.call('lib/svg_sprite.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
methods = owner.body.body.grep(Prism::DefNode)
select = lambda do |name|
  nodes = methods.select { |node| node.name == name }
  raise "SVG bundle method ambiguous #{name}" unless nodes.size == 1
  proof[:spans] << {method: name, sha256: Digest::SHA256.hexdigest(nodes.first.slice)}
  nodes.first.slice
end
constants = owner.body.body.grep(Prism::ConstantWriteNode)
icons = constants.find { |node| node.name == :SVG_ICONS }
sprite_name = constants.find { |node| node.name == :THEME_SPRITE_VAR_NAME }
raise 'SVG constant declaration changed' unless icons && sprite_name
names = %i[all_icons bundle core_svgs_files core_svgs plugin_svgs theme_svgs custom_svgs custom_icons symbols_for prepare_symbol]
raw = names.to_h { |name| [name, select.call(name)] }
field = read.call('app/models/theme_field.rb')
raise 'SVG Theme upload declaration changed' unless field.include?('theme_upload_var: 2,')
sprite_model = read.call('app/models/theme_svg_sprite.rb')
sprite_owner = Prism.parse(sprite_model).value.statements.body.grep(Prism::ClassNode).first
raise 'SVG sprite default-scope/callback profile changed' unless sprite_owner.body.body.all? { |node| (node.is_a?(Prism::CallNode) && node.name == :belongs_to && node.arguments.arguments.first.slice == ':theme') || (node.is_a?(Prism::DefNode) && node.name == :refetch! && node.receiver.is_a?(Prism::SelfNode)) }
File.write(File.join(build, 'svg_bundle_declarations.rb'), "module SvgBundleDeclarations\nTHEME_UPLOAD_TYPE = 2\n#{icons.slice.sub('SVG_ICONS', 'READ_ICON_SET')}\n#{sprite_name.slice.sub('THEME_SPRITE_VAR_NAME', 'READ_SPRITE_NAME')}\nend\n")
# Specialize the previously proved original bulk method, not another cache.
bulk_file = File.read(File.join(build, 'theme_bulk_cache_source.rb'))
bulk_nodes = []
walk_bulk = lambda do |node|
  bulk_nodes << node if node.is_a?(Prism::DefNode) && node.name == :defer_get_set_fields
  node.compact_child_nodes.each { |child| walk_bulk.call(child) }
end
walk_bulk.call(Prism.parse(bulk_file).value)
raise 'SVG typed bulk source ambiguous' unless bulk_nodes.size == 1
bulk = "module CategoryCacheApplication\nclass DistributedCache\n#{bulk_nodes.first.slice}\nend\nend\n"
bulk = bulk.sub('def defer_get_set_fields', 'def defer_get_set_theme_sprites').gsub('note_theme_field_value', 'note_svg_sprite_value').gsub('note_bulk_enqueue', 'note_svg_bulk_enqueue')
bulk = bulk.sub('hash.key?(key_blk.call(k))', '(hash.key?(key_blk.call(k)) && (ENV.fetch("FIDELITY_SVG_BUNDLE_FAULT", "") != "nil-as-miss" || !self[key_blk.call(k)].nil?))')
File.write(File.join(build, 'svg_bundle_bulk_source.rb'), bulk)
proof[:bulk_source_sha256] = Digest::SHA256.hexdigest(File.read(File.join(build, 'theme_bulk_cache_source.rb')))
common = raw.reject { |name, _| %i[symbols_for prepare_symbol all_icons].include?(name) }.values.join("\n")
common = common.gsub('.defer_get_set_bulk(', '.defer_get_set_theme_sprites(')
common = common.gsub('ThemeSvgSprite.where', 'SvgThemeSpriteRead.where')
common = common.gsub('ThemeField.types[:theme_upload_var]', 'SvgBundleDeclarations::THEME_UPLOAD_TYPE')
common = common.gsub('File.read(path)', 'SvgBundleBootstrap.read_svg(path)')
common = common.gsub('Rails.root.join(', 'File.join(RequestAssetCapability::ROOT, ')
common = common.sub('theme_field_uploads =', 'SvgBundleBootstrap.note_theme_query; theme_field_uploads =')
query = 'SvgThemeSpriteRead.where(theme_id: theme_ids).pluck(:theme_id, :upload_id, :sprite)'
raise 'SVG source theme sprite query changed' unless common.include?(query)
common = common.sub(query, query + "\n          raise ArgumentError, 'nonempty Theme SVG sprite profile unacquired' unless theme_sprites.empty?")
warning_nodes = []
visit_warning = lambda do |node|
  warning_nodes << node if node.is_a?(Prism::IfNode) && node.predicate.slice == 'missing_sprites.present?'
  node.compact_child_nodes.each { |child| visit_warning.call(child) }
end
visit_warning.call(Prism.parse(raw.fetch(:theme_svgs)).value)
raise 'SVG source missing sprite warning changed' unless warning_nodes.size == 1
warn = warning_nodes.first.slice
raise 'SVG source missing sprite warning span absent' unless common.include?(warn)
common = common.sub(warn, "raise ArgumentError, 'unowned missing Theme SVG sprite logging profile' if missing_sprites.present?")
# No loaded plugin profile remains explicit before optional plugin path access.
common = common.sub('plugin_paths = []', "raise ArgumentError, 'unacquired loaded plugin SVG paths' unless Discourse.plugins.empty?\n        plugin_paths = []")
File.write(File.join(build, 'original_svg_bundle_source.rb'), <<~RUBY)
  require 'nokogiri'
  require 'active_support/core_ext/object/blank'
  module OriginalRequestSvgSource
    SVG_ICONS = SvgBundleDeclarations::READ_ICON_SET
    THEME_SPRITE_VAR_NAME = SvgBundleDeclarations::READ_SPRITE_NAME
    #{raw.fetch(:all_icons)}
    #{common}
    #{raw.fetch(:symbols_for)}
    #{raw.fetch(:prepare_symbol)}
    def self.get_set_cache(key)
      RequestSvgBootstrap.note_cache(key, cache)
      if key.start_with?('version_')
        cache.defer_get_set(key) do
          value = yield
          CategoryCacheBootstrap.lease.note_svg_version(key, value)
          value
        end
      else
        cache.defer_get_set_svg_icons(key) { yield }
      end
    end
  end
RUBY
native = common.gsub('theme_id.present?', 'ActiveSupport.present?(theme_id)').gsub('theme_id.blank?', 'ActiveSupport.blank?(theme_id)').gsub('missing_sprites.present?', 'ActiveSupport.present?(missing_sprites)')
native = native.gsub('THEME_SPRITE_VAR_NAME', 'READ_SPRITE_NAME')
# Alias source method cache domains explicitly; no precomputed icons or XML.
native = native.gsub('get_set_cache(', 'get_set_cache_icons(')
map_nodes = []
visit_map = lambda do |node|
  map_nodes << node if node.is_a?(Prism::CallNode) && node.name == :map && node.block.is_a?(Prism::BlockNode) && node.receiver && node.receiver.slice == 'theme_sprites'
  node.compact_child_nodes.each { |child| visit_map.call(child) }
end
visit_map.call(Prism.parse(native).value)
raise 'SVG theme sprite map ambiguous' unless map_nodes.size == 1
native = native.sub(map_nodes.first.slice, "theme_sprites.map { |row| raise ArgumentError, 'nonempty Theme SVG sprite profile unacquired' }")

all = raw.fetch(:all_icons).gsub('get_set_cache(', 'get_set_cache_icons(').gsub('i.blank?', 'ActiveSupport.blank?(i)')
all = all.sub('.merge(SVG_ICONS)', '.merge(ENV.fetch("FIDELITY_SVG_BUNDLE_FAULT", "") == "drop-core-icon" ? Set.new(SVG_ICONS.to_a.drop(1)) : SVG_ICONS)')
# Genuine source plugin registry is empty in this guarded no-plugins milestone;
# refuse at first nonempty path collaborator rather than inventing paths.
plugin_nodes = []
visit_plugin = lambda do |node|
  plugin_nodes << node if node.is_a?(Prism::CallNode) && node.name == :each && node.slice.start_with?('Discourse')
  node.compact_child_nodes.each { |child| visit_plugin.call(child) }
end
visit_plugin.call(Prism.parse(raw.fetch(:plugin_svgs)).value)
raise 'SVG plugin source walk ambiguous' unless plugin_nodes.size == 1
original_plugin_walk = plugin_nodes.first.slice
raise 'SVG source plugin path walk changed' unless native.include?(original_plugin_walk)
native = native.sub(original_plugin_walk, "Discourse.plugins.each { |plugin| raise ArgumentError, 'unacquired loaded plugin SVG paths' }")
all = all.gsub('SVG_ICONS', 'READ_ICON_SET')
File.write(File.join(build, 'svg_bundle_source.rb'), <<~RUBY)
  module RequestSvgSource
    READ_ICON_SET = SvgBundleDeclarations::READ_ICON_SET
    READ_SPRITE_NAME = SvgBundleDeclarations::READ_SPRITE_NAME
    #{all}
    #{native}
    def self.symbols_for(filename, source, strict:)
      SvgBundleBootstrap.symbols_for(filename, source, strict: strict)
    end
    def self.get_set_cache_version(key)
      RequestSvgBootstrap.note_cache(key, cache)
      cache.defer_get_set(key) do
        value = yield
        value += '-wrong' if ENV.fetch('FIDELITY_SVG_BUNDLE_FAULT', '') == 'wrong-version'
        CategoryCacheBootstrap.lease.note_svg_version(key, value)
        value
      end
    end
  end
RUBY
proof[:transformations] = ['Complete source all_icons Set merge/filter/map/constant/sort order and bundle/core/plugin/custom methods', 'Source theme field/sprite readonly plucks and real original nil bulk cache; nonempty sprite or missing-sprite logger profile explicitly refuses', 'Actual verified source SVG bytes into stateless SAME native/shared XML engine; independent original raw symbols_for/prepare_symbol via actual Nokogiri', 'Scoped source core files root/read capability binding only; cache versions computed from actual XML, no captured symbols/digests/paths', 'No-loaded-plugin guard retains actual empty registry iteration, nonempty path callback profile refuses']
File.write(File.join(build, 'svg-bundle-source-proof.json'), JSON.pretty_generate(proof) + "\n")
