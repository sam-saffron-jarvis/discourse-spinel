# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false, stylesheet_acquired: false}
read = lambda do |path|
  value, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "stylesheet key source changed #{path}" unless status.success? && value.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(value)
  value
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "stylesheet key ambiguous method #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
slug = read.call('lib/slug.rb')
base = Prism.parse(read.call('lib/enum_site_setting.rb')).value.statements.body.grep(Prism::ClassNode).first
raise 'SlugSetting base acquired wrapper' unless base.body.body.all? { |n| n.is_a?(Prism::DefNode) && n.receiver && %i[translate_names? wrap_values!].include?(n.name) }
enum = Prism.parse(read.call('app/models/slug_setting.rb')).value.statements.body.grep(Prism::ClassNode).first
raise 'SlugSetting acquired wrapper/callback' unless enum.superclass.slice == 'EnumSiteSetting' && enum.body.body.all? { |n| n.is_a?(Prism::ConstantWriteNode) && n.name == :VALUES || n.is_a?(Prism::DefNode) && n.receiver && %i[values valid_value?].include?(n.name) }
emoji = Prism.parse(read.call('app/models/emoji.rb')).value.statements.body.grep(Prism::ClassNode).first.body.body.grep(Prism::ConstantWriteNode).find { |n| n.name == :EMOJI_CODE_REGEXP }.slice
read.call('config/database.yml')
read.call('app/models/global_setting.rb')
manager = read.call('lib/stylesheet/manager.rb')
key = select.call(manager, :color_scheme_cache_key)
constant = Prism.parse(manager).value.statements.body.grep(Prism::ClassNode).first.body.body.grep(Prism::ConstantWriteNode).find { |n| n.name == :COLOR_SCHEME_STYLESHEET }.slice
# The existing parameterize runtime has no transliteration. Admit ASCII only,
# preserving all source slug branches inside that explicitly bounded domain.
native = slug.sub('def self.for(string, default = "topic", max_length = MAX_LENGTH, method: nil)', 'def self.for(string, default = "topic", max_length = MAX_LENGTH, method: nil)' + "\n    raise ArgumentError, 'unacquired non-ASCII stylesheet slug transliteration' unless string.ascii_only?")
native = native.sub(%q{string.tr("'", "").parameterize}, %q{Inflector.parameterize(string.tr("'", ""))})
native = native.sub('CGI.escape(string)', 'ActionView::ViewHelpers.url_encode(string)')
File.write(File.join(app, 'app/models/stylesheet_slug.rb'), native)
bindings = <<~RUBY
  module OriginalStylesheetPrimitives
    refine Object do
      def present?; ::ActiveSupport.present?(self); end
      def blank?; ::ActiveSupport.blank?(self); end
    end
    refine String do
      def parameterize; ::Inflector.parameterize(self); end
      def truncate(length, omission: "..."); ::ActiveSupport.truncate(self, length, omission, nil); end
    end
  end
RUBY
original = slug.sub('module Slug', "module OriginalStylesheetSlug\nusing OriginalStylesheetPrimitives")
original = original.sub('  CHAR_FILTER_REGEXP', <<~RUBY + '  CHAR_FILTER_REGEXP')
  module I18n
    def self.with_locale(locale)
      previous = ::I18n.enter_locale(locale)
      begin
        yield
      ensure
        ::I18n.leave_locale(previous)
      end
    end
  end
RUBY
File.write(File.join(build, 'original_stylesheet_slug.rb'), bindings + original)
File.write(File.join(build, 'stylesheet_key_source.rb'), "module StylesheetKeySource\n#{constant}\n#{key}\nend\n")
File.write(File.join(build, 'original_stylesheet_key_source.rb'), "module OriginalStylesheetKeySource\n#{constant}\nSlug = OriginalStylesheetSlug\n#{key}\nend\n")
path = File.join(app, 'app/models/color_scheme.rb')
File.write(path, File.read(path).sub(/end\s*\z/, <<~RUBY))
  def read_attribute(name)
    raise ArgumentError, 'unacquired stylesheet raw attribute' unless name == :name
    value = @name
    raise ArgumentError, 'stylesheet raw name must be String' unless value.is_a?(String)
    value
  end
end
RUBY
# Keep an independent actual ActiveRecord + ActiveSupport/I18n evaluation. It
# reads the shared provider fresh in its own guarded process, never a candidate
# diagnostic/key as input. No Rails app/HTML bootstrap or cache/build dispatch.
raw = File.read(File.join(build, 'raw_palette_base_reference.rb'))
raw += <<~RUBY
  require 'active_support/core_ext/string/inflections'
  require 'active_support/core_ext/string/filters'
  require 'cgi'
  require #{File.join(root, 'fidelity/compat/discourse/lib/site_settings/portable_pg_provider.rb').dump}
  require #{File.join(root, 'fidelity/compat/discourse/lib/site_settings/portable_stylesheet_slug_reader.rb').dump}
  require #{File.join(root, 'fidelity/compat/discourse/lib/site_settings/portable_core_definitions.rb').dump}
  module RawStylesheetBindings
    class << self; attr_accessor :store, :site, :configuration; end
  end
  module SiteSetting
    def self.slug_generation_method; RawStylesheetBindings.store.stylesheet_slug_current(RawStylesheetBindings.site); end
    def self.default_locale; RawStylesheetBindings.store.get('default_locale', RawStylesheetBindings.site); end
    def self.force_hostname; RawStylesheetBindings.store.get('force_hostname', RawStylesheetBindings.site); end
  end
  module RailsMultisite
    module ConnectionManagement
      def self.current_hostname; RawStylesheetBindings.configuration.database_hostname; end
    end
  end
  module Discourse
    #{select.call(read.call('lib/discourse.rb'), :current_hostname)}
  end
  module GlobalSetting
    def self.relative_url_root; RawStylesheetBindings.configuration.value('relative_url_root'); end
  end
  class Emoji
    #{emoji}
  end
  #{slug}
  module RawStylesheetKeySource
    #{constant}
    #{key}
  end
  ActiveRecord::Base.connection_pool.with_connection do |connection|
    definitions = SiteSettings::PortableCoreDefinitions.build
    configuration = SiteSettings::PortableGlobalConfiguration.new(definitions, #{File.join(root, 'discourse/config/discourse_defaults.conf').dump}, #{File.join(root, 'discourse/config/discourse.conf').dump})
    site = connection.select_value('SELECT current_database()')
    provider = SiteSettings::PortablePgProvider.new({site => connection.raw_connection}, configuration)
    RawStylesheetBindings.configuration = configuration
    RawStylesheetBindings.site = site
    RawStylesheetBindings.store = SiteSettings::PortableReadStore.new(definitions, provider)
    theme_id = RawStylesheetBindings.store.get('default_theme_id', site)
    record = ColorScheme.base
    keys = [nil, theme_id].map { |id| RawStylesheetKeySource.color_scheme_cache_key(record, id) }
    units = #{['A_B \' test--42', '123', ':smile:', 'A' * 280].inspect}.map { |text| Slug.for(text) }
    puts 'FIDELITY_RAW_STYLESHEET_KEY ' + JSON.generate({keys: keys, units: units, hostname: Discourse.current_hostname, relative_url_root: GlobalSetting.relative_url_root, slug_method: SiteSetting.slug_generation_method, default_locale: SiteSetting.default_locale})
  end
  ActiveRecord::Base.connection_pool.disconnect!
RUBY
File.write(File.join(build, 'raw_stylesheet_key_reference.rb'), raw)
_, parameterize = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/inflector/transliterate.rb')
proof[:framework] = [parameterize]
proof[:adaptations] = ['Complete source Slug algorithm; ASCII admission refuses unacquired transliteration, no forced method or skipped slug/default-locale getters', 'Existing URL encoder binds CGI.escape; actual source emoji regex already acquired', 'Exact no-wrap SlugSetting base/class proof, fresh shared provider read and strict callback metadata guard, no generic scalar admission change', 'Raw read_attribute(:name) binds actual raw slot, not localized name; unknown attributes/types refuse', 'Actual existing force_hostname/database_hostname chain and global File/Env provider, no supplied cache key/URL', 'Independent actual AR/ActiveSupport/I18n source reference with fresh guarded provider and live configuration, no Rails app or build dispatch']
File.write(File.join(build, 'stylesheet-key-source-proof.json'), JSON.pretty_generate(proof) + "\n")
