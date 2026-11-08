# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:lib/svg_sprite.rb")
raise 'SVG source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/lib/svg_sprite.rb'))
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
names = %i[path version bundle all_icons settings_icons get_set_cache cache badge_icons group_icons]
nodes = owner.body.body.grep(Prism::DefNode).select { |n| names.include?(n.name) }
raise 'SVG method set changed' unless nodes.map(&:name).sort == names.sort
methods = nodes.to_h { |n| [n.name, n.slice] }
cache = methods[:cache].sub('DistributedCache.new("svg_sprite")', 'CategoryCacheBootstrap.svg_cache')
path = methods[:path]
version = methods[:version].sub('get_set_cache(', 'get_set_cache_version(')
# Actual original call order only through the first unacquired collaborator;
# no later chain step or partial result is represented as executed.
bundle_node = nodes.find { |n| n.name == :bundle }
first = bundle_node.body.body.first.slice
raise 'SVG bundle prefix changed' unless first == 'icons = all_icons(theme_id)'
settings_node = nodes.find { |n| n.name == :settings_icons }
raise 'SVG settings acquisition changed' unless settings_node.slice.include?('SiteSetting.settings_hash.each')
all_node = nodes.find { |n| n.name == :all_icons }
raise 'SVG all_icons prefix changed' unless all_node.slice.include?('get_set_cache("icons_#{Theme.transform_ids(theme_id).join(",")}")') && all_node.slice.include?('.merge(settings_icons)')
leaf = %i[badge_icons group_icons].map { |name| methods[name].sub('get_set_cache(', 'get_set_cache_icons(') }.join("\n")
File.write(File.join(build, 'svg_cache_source.rb'), <<~'RUBY'.sub('CACHE_METHOD', cache).sub('PATH_METHOD', path).sub('VERSION_METHOD', version).sub('LEAF_METHODS', leaf))
  require 'set'
  module RequestSvgSource
    module Theme
      def self.transform_ids(id); ListThemeCompilerSource.transform_ids(id); end
    end
    CACHE_METHOD
    PATH_METHOD
    VERSION_METHOD
    LEAF_METHODS
    def self.get_set_cache_version(key)
      RequestSvgBootstrap.note_cache(key, cache)
      cache.defer_get_set(key) { yield }
    end
    def self.get_set_cache_icons(key)
      RequestSvgBootstrap.note_cache(key, cache)
      cache.defer_get_set_svg_icons(key) { yield }
    end
    def self.bundle(theme_id = nil)
      icons = all_icons(theme_id)
      raise 'SVG bundle prefix unexpectedly returned'
    end
    def self.all_icons(theme_id = nil)
      get_set_cache_icons("icons_#{Theme.transform_ids(theme_id).join(',')}") do
        Set.new.merge(settings_icons)
        raise 'SVG all_icons prefix unexpectedly returned'
      end
    end
    def self.settings_icons
      get_set_cache_icons('settings_icons') do
        site_setting_icons = []
        RequestSvgBootstrap.settings_hash
        raise 'SVG settings hash boundary unexpectedly returned'
      end
    end
  end
RUBY
raw = nodes.map(&:slice).join("\n")
# Original executes full original chain, with the same explicit cache factory
# binding and the same refusal at the settings_hash collaborator.
raw = raw.sub(methods[:cache], cache).sub(methods[:get_set_cache], <<~'RUBY'.strip)
  def self.get_set_cache(key, &block)
    RequestSvgBootstrap.note_cache(key, cache)
    cache.defer_get_set_svg_reference(key) { yield }
  end
RUBY
File.write(File.join(build, 'original_svg_cache_source.rb'), <<~RUBY)
  module OriginalRequestSvgSource
    Theme = RequestSvgSource::Theme
    module SiteSetting
      def self.settings_hash; RequestSvgBootstrap.settings_hash; end
    end
    #{raw}
  end
RUBY
File.write(File.join(app, 'app/models/badge.rb'), "class Badge < ActiveRecord::Base\nend\n")
File.write(File.join(build, 'svg-cache-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), spans: nodes.map { |n| {method: n.name, start: n.location.start_offset, end: n.location.end_offset, sha256: Digest::SHA256.hexdigest(n.slice)} }, transformations: ['Actual path/version/cache and source-order bundle/all_icons/settings_icons prefix, explicit refusal before settings_hash acquisition', 'Original reference executes complete selected original methods through same unacquired collaborator', 'Separate typed nullable String Array getter on existing original cache; other domains remain strict', 'Badge/Group icon producers only in separate UNIT read proof, never seeded into request cache'], page_accepted: false}) + "\n")
