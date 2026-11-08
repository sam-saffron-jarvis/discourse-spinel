# frozen_string_literal: true
# Extend the SAME actual layout through the first locale preload, not a page.
require 'prism'
require 'digest'
require 'json'
require 'open3'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "locale layout source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |text, name|
  found = []
  visit = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(text).value)
  raise "locale method ambiguous #{name}" unless found.size == 1
  node = found.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
controller = read.call('app/controllers/extra_locales_controller.rb')
klass = Prism.parse(controller).value.statements.body.grep(Prism::ClassNode).first
constants = klass.body.body.grep(Prism::ConstantWriteNode).map(&:slice).join("\n")
extra_names = %i[js_digests bundle_js_hash url client_overrides_exist? bundle_js digest_for_content clear_cache!]
original_extra = extra_names.map { |name| select.call(controller, name) }
File.write(File.join(build, 'original_extra_locale_source.rb'), "module OriginalExtraLocaleSource\n#{constants}\nclass << self\n#{original_extra.join("\n")}\nend\nend\n")
native_extra = %i[bundle_js_hash url client_overrides_exist? digest_for_content].map { |name| select.call(controller, name) }.map do |text|
  text = text.sub(/^def /, 'def self.')
  result = text.gsub('js_digests[:shared]', 'shared_js_digests').gsub('js_digests[:site_specific]', 'site_js_digests').gsub('bundle.in?(SITE_SPECIFIC_BUNDLES)', 'SITE_SPECIFIC_BUNDLES.include?(bundle)').gsub('bundle.in?(SHARED_BUNDLES)', 'SHARED_BUNDLES.include?(bundle)').gsub('js.present?', 'ActiveSupport.present?(js)').gsub('bundle_js_hash(OVERRIDES_BUNDLE, locale: locale).present?', 'ActiveSupport.present?(bundle_js_hash(OVERRIDES_BUNDLE, locale: locale))').gsub('GlobalSetting.cdn_url', 'ListHeadImages.configuration.value("cdn_url")')
  result = result.sub('hash = bundle_js_hash(bundle, locale:)', 'RequestClientLocaleBootstrap.events << "locale_bundle_acquisition:#{bundle}"; hash = bundle_js_hash(bundle, locale:)') if text.start_with?('def url(') || text.start_with?('def self.url(')
  result
end
File.write(File.join(build, 'request_extra_locale_source.rb'), <<~RUBY)
  class ExtraLocalesController
    RailsMultisite = CategoryCacheApplication::RailsMultisite
    #{constants}
    def self.shared_js_digests; @shared_js_digests ||= {}; end
    def self.site_js_digests; @site_js_digests ||= {}; end
    #{native_extra.join("\n")}
    def self.bundle_js(bundle, locale:)
      previous = I18n.enter_locale(locale)
      begin
        case bundle
        when MAIN_BUNDLE
          RequestClientLocaleBootstrap.build_main(locale.to_s)
        when MF_BUNDLE
          raise HtmlRenderingBoundary, 'actual main locale JS/digest/preload acquired; MessageFormat compiler acquisition pending'
        else
          raise ArgumentError, 'unsupported locale bundle before MessageFormat acquisition'
        end
      ensure
        I18n.leave_locale(previous)
      end
    end
  end
RUBY
File.write(File.join(build, 'request_extra_locale_source.rbs'), <<~RBS)
  class ExtraLocalesController
    def self.shared_js_digests: () -> Hash[String, String]
    def self.site_js_digests: () -> Hash[String, Hash[String, String?]]
    def self.bundle_js_hash: (String bundle, locale: String | Symbol) -> String?
    def self.url: (String bundle, ?locale: String | Symbol) -> String
    def self.bundle_js: (String bundle, locale: String | Symbol) -> String
    def self.digest_for_content: (String js) -> String
  end
RBS
# This is the exact original accelerator READ, not an invented query or SQL.
accelerator = read.call('lib/freedom_patches/translate_accelerator.rb')
raise 'date override read source changed' unless accelerator.include?('TranslationOverride.where(locale: locale).pluck(:translation_key, :value)')
read.call('app/models/translation_override.rb')
File.write(File.join(app, 'app/models/translation_override.rb'), "class TranslationOverride < ActiveRecord::Base\nend\n")
File.write(File.join(build, 'original_locale_boot.rb'), <<~'RUBY')
  require_relative 'original_request_asset_boot'
  require 'active_support/json'
  OriginalClientJSONEncode = ActiveSupport::JSON.method(:encode)
RUBY
backend = read.call('lib/i18n/backend/discourse_i18n.rb')
proof[:framework] = []
i18n_source, metadata = FidelitySourcePackage.member(root, 'i18n-1.14.8', 'lib/i18n.rb')
proof[:framework] << metadata
simple_source, metadata = FidelitySourcePackage.member(root, 'i18n-1.14.8', 'lib/i18n/backend/simple.rb')
proof[:framework] << metadata
simple_lookup = select.call(simple_source, :lookup).gsub('I18n.normalize_keys', 'OriginalClientI18nNormalizer.normalize_keys')
normalizers = %i[normalize_keys normalize_key].map { |name| select.call(i18n_source, name).sub('def ', 'def self.') }
lookup = select.call(backend, :lookup)
File.write(File.join(build, 'original_client_date_backend.rb'), <<~RUBY)
  # Original Simple/Discourse lookup with its original normalization namespace,
  # isolated from the lowered one-argument I18n.normalize_key protocol.
  module OriginalClientI18nNormalizer
    @@normalized_key_cache = ::I18n.new_double_nested_cache
    #{normalizers.join("\n")}
  end
  class OriginalClientDateBase < I18n::Backend::Simple
    EMPTY_HASH = I18n::EMPTY_HASH
    Utils = I18n::Utils
    #{simple_lookup}
  end
  class OriginalClientDateBackend < OriginalClientDateBase
    #{lookup}
  end
RUBY
%w[lib/active_support/hash_with_indifferent_access.rb lib/active_support/core_ext/hash/deep_merge.rb lib/active_support/core_ext/object/json.rb lib/active_support/json/encoding.rb].each do |path|
  _, metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', path)
  proof[:framework] << metadata
end
helper = read.call('app/helpers/application_helper.rb')
preloads = %i[preload_script_url add_resource_preload_list].map { |name| select.call(helper, name) }
raw_plugin = select.call(helper, :build_plugin_html)
registry = read.call('lib/discourse_plugin_registry.rb')
raise 'plugin HTML lazy Hash declaration changed' unless registry.include?('define_register :html_builders, Hash')
raw_build = select.call(registry, :build_html)
original_helpers = "module OriginalLocaleLayoutHelpers\n#{raw_plugin}\n#{preloads.join("\n")}\nend\n"
original_helpers << "class DiscoursePluginRegistry\ndef self.html_builders; @html_builders ||= {}; end\n#{raw_build}\nend\n"
File.write(File.join(build, 'original_locale_layout_helpers.rb'), original_helpers)
native_preloads = preloads.map do |text|
  text = text.sub('controller.instance_variable_get(:@asset_preload_links)', 'controller.asset_preload_links').sub('controller.instance_variable_set(:@asset_preload_links, [])', '(controller.asset_preload_links = [])')
  if text.start_with?('def add_resource_preload_list(')
    anchor = "links =\n      controller.asset_preload_links ||\n        (controller.asset_preload_links = [])"
    raise 'original preload storage anchor changed' unless text.include?(anchor)
    text = text.sub(anchor, "links = controller.asset_preload_links\n    unless links\n      controller.asset_preload_links = []\n      links = controller.asset_preload_links\n    end")
  end
  text = text.sub('if extra_attrs.present?', 'if extra_attrs && !extra_attrs.empty?').sub('<<~HTML.html_safe', 'ActionView::HtmlFragment.new(<<~HTML)')
  text
end
File.write(File.join(build, 'request_locale_layout_helpers.rb'), <<~RUBY)
  module RequestLocaleLayoutHelpers
    #{raw_plugin}
    #{native_preloads.join("\n")}
  end
  class DiscoursePluginRegistry
    def self.html_builders; @html_builders ||= {}; end
    def self.build_html(name, ctx = nil, **kwargs)
      raise ArgumentError, 'unsupported loaded plugin HTML builders' unless Discourse.plugins.empty? && html_builders.empty?
      ActionView::HtmlFragment.new('')
    end
  end
RUBY
layout = read.call('app/views/layouts/application.html.erb')
anchor = '<%= preload_script_url ExtraLocalesController.url("mf"), type_module: true %>'
last = layout.index(anchor)
raise 'locale layout continuation anchor changed' unless last
prefix = layout[0, last + anchor.length].gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
%w[request_extra_locale_source.rb original_extra_locale_source.rb request_locale_layout_helpers.rb native_locale_layout.rb original_client_date_backend.rb].each do |name|
  raise "invalid generated locale source #{name}" unless Prism.parse_file(File.join(build, name)).success?
end
proof[:transformations] = ['Original typed shared/site-specific locale digest cache slots, digest/version/URL source retained', 'Main bundle executes source client YAML helper; next MF branch explicitly refuses before missing capability', 'Exact source accelerator TranslationOverride read; no PG write methods imported', 'Original build_plugin_html and typed preload storage; empty builder loop folds only after runtime registry check', 'Native actual application template prefix through next MF URL; third original still uses full template']
File.write(File.join(build, 'locale-layout-source-proof.json'), JSON.pretty_generate(proof) + "\n")
