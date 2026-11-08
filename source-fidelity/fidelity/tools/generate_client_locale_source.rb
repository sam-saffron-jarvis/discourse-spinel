# frozen_string_literal: true
# Source-owned client-locale generation; no observed JS or digests supplied.
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "client locale source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
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
  raise "client locale method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
registry = read.call('lib/discourse_plugin_registry.rb')
raise 'client locale registry declaration changed' unless registry.include?('define_register :locales, ActiveSupport::HashWithIndifferentAccess')
plugins = select.call(read.call('lib/discourse.rb'), :plugins)
File.write(File.join(build, 'client_locale_registry.rb'), "module Discourse\n#{plugins}\nend\nclass DiscoursePluginRegistry\ndef self.locales; @locales ||= {}; end\nend\n")
proof[:registry_binding] = 'Original lazy locales HashWithIndifferentAccess slot specialized to String-only lookup Hash; actual Discourse.plugins source, no loaded plugins'
source = read.call('lib/js_locale_helper.rb')
names = %i[plugin_client_files plugin_translations load_translations deep_delete_matches load_translations_merged clear_cache! translations_for output_locale output_MF find_moment_locale find_locale moment_formats moment_format_function moment_ascii_digits moment_locale remove_message_formats! strip_out_message_formats! join_key]
methods = names.map { |name| select.call(source, name) }
sort = select.call(read.call('lib/i18n/backend/discourse_i18n.rb'), :sort_locale_files)
raw = "module OriginalClientLocaleSource\nMOMENT_LOCALE_MAPPING = #{source[/MOMENT_LOCALE_MAPPING = (\{[^\n]+\})/, 1]}\n#{methods.join("\n")}\nend\n"
File.write(File.join(build, 'original_client_locale_source.rb'), raw)
# Instance binding makes the source caches explicitly owned by the admitted
# request. Indifferent cache keys are normalized to String, never runtime data.
native = methods.map do |text|
  text = text.sub('def self.', 'def ')
  text = text.gsub('Rails.root.join(', 'File.join(@root, ')
  text = text.gsub('Rails.env.development?', '@environment.development?')
  text = text.gsub('I18n::Backend::DiscourseI18n.sort_locale_files(files)', 'sort_locale_files(files)')
  text = text.gsub('YAML.load_file(', 'load_client_yaml(').gsub('File.read(filename)', 'read_client_source(filename)')
  text = text.gsub('ActiveSupport::HashWithIndifferentAccess.new', '{}')
  text = text.gsub('@loaded_translations[locale]', '@loaded_translations[locale.to_s]')
  text = text.gsub('I18n.fallbacks[locale]', 'fallbacks(locale)').gsub('I18n.fallbacks[locale_sym]', 'fallbacks(locale_sym)')
  text = text.gsub('locale_sym == :en || no_fallback', 'locale_sym == :en || no_fallback')
  text = text.gsub('LocaleSiteSetting.fallback_locale(locale_str)&.to_s', 'fallback_locale(locale_str)&.to_s')
  text = text.gsub('I18n.t("dates.#{name}")', 'date_translation(name)')
  text = text.gsub('translations.to_json', 'client_json(translations)')
  text = text.gsub('path = "#{VendoredAssets.path("moment-timezone-names/locales")}"', 'path = File.join(@root, "vendor/runtime_node_modules/moment-timezone-names/locales")')
  text = text.gsub('path = "#{VendoredAssets.path("moment/locale")}"', 'path = File.join(@root, "vendor/runtime_node_modules/moment/locale")')
  text = text.gsub('DiscoursePluginRegistry.locales[locale]', 'plugin_locale(locale)')
  if text.start_with?('def output_MF(')
    text = text.sub('require "messageformat"', 'ensure_messageformat_compiler!')
    text = text.gsub('hash[l]', 'hash[l.to_s]').gsub('message_formats[locale]', 'message_formats[locale.to_s]')
    text = text.gsub('MessageFormat.compile(', 'compile_messageformat(')
    # Error validation consumes read-only String bytes; give the platform call
    # owned copies rather than captured Strings passed through a variadic FFI.
    text = text.sub('compile_messageformat(js_locale, value, strict: false)', 'compile_messageformat(js_locale.dup, value.dup, strict: false)')
    text = text.gsub('message_formats.transform_keys(&:dasherize)', 'message_formats.transform_keys { |key| key.tr("_", "-") }')
    text = text.gsub('.to_s.dasherize', '.to_s.tr("_", "-")')
    text = text.gsub('.compact_blank', '.reject { |_locale, value| ActiveSupport.blank?(value) }')
    text = text.gsub('result.indent(2)', 'result.gsub(/^(?!$)/, "  ")')
    text = text.gsub('Rails.logger.error(', 'log_messageformat_error(')
  end
  if text.start_with?('def translations_for(')
    anchor = <<~'SOURCE'.chomp
      translations =
            I18n.with_locale(locale_sym) do
              if locale_sym == :en || no_fallback
                load_translations(locale_sym)
              else
                load_translations_merged(*fallbacks(locale_sym))
              end
            end
    SOURCE
    replacement = <<~'SOURCE'.chomp
      previous = I18n.enter_locale(locale_sym)
          begin
            translations = if locale_sym == :en || no_fallback
              load_translations(locale_sym)
            else
              load_translations_merged(*fallbacks(locale_sym))
            end
          ensure
            I18n.leave_locale(previous)
          end
    SOURCE
    raise 'client locale scope anchor changed' unless text.include?(anchor)
    text = text.sub(anchor, replacement)
  end
  text = text.gsub('name.camelize(:lower)', 'ActiveSupport::Inflector.camelize(name, false)')
  merges = []
  visit_merges = lambda do |node|
    if node.is_a?(Prism::CallNode) && node.name == :deep_merge!
      merges << node
    else
      node.compact_child_nodes.each { |child| visit_merges.call(child) }
    end
  end
  visit_merges.call(Prism.parse(text).value)
  merges.sort_by { |node| -node.location.start_offset }.each do |node|
    text[node.location.start_offset, node.location.length] = "merge_translations!(#{node.receiver.slice}, #{node.arguments.slice})"
  end
  if text.start_with?('def strip_out_message_formats!')
    text = text.sub('hash.each do |key, value|', 'hash.keys.each do |key|; value = hash[key]')
  end
  text = text.gsub('prefix.blank?', 'ActiveSupport.blank?(prefix)')
  text
end
fallback_source = read.call('lib/i18n/backend/fallback_locale_list.rb')
File.write(File.join(build, 'original_client_fallbacks.rb'), fallback_source)
fallback = select.call(fallback_source, :[]).sub('def [](locale)', 'def fallbacks(locale)').gsub('LocaleSiteSetting.fallback_locale(locale)', 'fallback_locale(locale)')
locale_settings = read.call('app/models/locale_site_setting.rb')
locale_fallback_original = select.call(locale_settings, :fallback_locale)
fallback_constant = locale_settings[/^  FALLBACKS = (.*)$/, 1]
raise 'locale fallback declaration missing' unless fallback_constant
File.write(File.join(build, 'original_client_locale_bindings.rb'), "class DiscoursePluginRegistry\ndef self.locales; @locales ||= ActiveSupport::HashWithIndifferentAccess.new; end\nend\nclass LocaleSiteSetting\nFALLBACKS = #{fallback_constant}\n#{locale_fallback_original}\nend\nmodule I18n::Backend\nclass DiscourseI18n\n#{sort}\nend\nend\n")
locale_fallback = locale_fallback_original.sub('def self.', 'def ').gsub('DiscoursePluginRegistry.locales[locale.to_s]', 'plugin_locale(locale.to_s)')
constants = "FALLBACKS = #{locale_settings[/FALLBACKS = (\{[^\n]+\})/, 1]}\nMOMENT_LOCALE_MAPPING = #{source[/MOMENT_LOCALE_MAPPING = (\{[^\n]+\})/, 1]}"
body = <<~RUBY
  require 'yaml'
  require 'json'
  require 'erb'
  class RequestClientLocaleSource
    #{constants}
    def initialize(root, environment)
      @root = root
      @environment = environment
      @loaded_translations = nil
      @plugin_translations = nil
      @loaded_merges = nil
    end
    def plugin_locale(locale)
      raise ArgumentError, 'unsupported loaded client locale plugins' unless client_plugins_empty?
      DiscoursePluginRegistry.locales[locale]
    end
    def client_plugins_empty?; Discourse.plugins.empty?; end
    def ensure_messageformat_compiler!; raise ArgumentError, 'unbound actual MessageFormat compiler'; end
    def compile_messageformat(locales, messages, strict: true); raise ArgumentError, 'unbound actual MessageFormat compiler'; end
    def log_messageformat_error(message); raise ArgumentError, 'unbound owned MessageFormat error logger'; end
    def load_client_yaml(path); YAML.load_file(path); end
    def read_client_source(path); File.read(path); end
    def merge_translations!(left, right)
      left.replace(ActiveSupport.deep_merge(left, right))
    end
    def date_translation(name)
      locale = I18n.locale.to_s
      data = YAML.load_file(File.join(@root, "config/locales/server.\#{locale}.yml"), aliases: true)
      value = data.dig(locale, 'dates', name)
      raise TypeError, 'client date source is not String' unless value.is_a?(String)
      value
    end
    def client_json(value)
      # Original Rails Hash#to_json uses ActiveSupport JSON's default HTML
      # entity escaping. Explicit binding avoids a plain JSON-gem substitute.
      JsonBuilder.escape_html_entities(JSON.generate(value))
    end
    #{sort.sub('def self.', 'def ')}
    #{fallback}
    #{locale_fallback}
    #{native.join("\n\n")}
  end
RUBY
raise 'invalid client locale projection' unless Prism.parse(body).success?
File.write(File.join(build, 'request_client_locale_source.rb'), body)
File.write(File.join(build, 'request_client_locale_source.rbs'), <<~RBS)
  class RequestClientLocaleSource
    @root: String
    @loaded_translations: Hash[String, untyped]?
    @plugin_translations: Hash[String, untyped]?
    @loaded_merges: Hash[String, untyped]?
    def load_client_yaml: (String path) -> Hash[String, untyped]
    def read_client_source: (String path) -> String
    def merge_translations!: (Hash[String, untyped] left, Hash[String, untyped] right) -> Hash[String, untyped]
    def plugin_locale: (String locale) -> Hash[Symbol, String]?
    def sort_locale_files: (Array[String] files) -> Array[String]
    def plugin_translations: (String locale_str) -> Hash[String, untyped]
    def load_translations: (String | Symbol locale) -> Hash[String, untyped]
    def translations_for: (String | Symbol locale_str, ?no_fallback: bool) -> Hash[String, untyped]
    def output_MF: (String locale) -> String
    def compile_messageformat: (String | Array[String] locales, String | Hash[String, untyped] messages, ?strict: bool) -> String
    def load_translations_merged: (*(String | Symbol)? locales) -> Hash[String, untyped]
    def deep_delete_matches: (Hash[String, untyped] deleting_from, Array[untyped] checking_hashes) -> Hash[String, untyped]
    def remove_message_formats!: (Hash[String, untyped] translations, String | Symbol locale) -> Hash[String, String]
    def strip_out_message_formats!: (untyped hash, ?String prefix, ?Hash[String, String] message_formats) -> Hash[String, String]
    def find_locale: (Array[String] locale_chain, String path, Symbol type, fallback_to_english: bool) { (String) -> String } -> Array[String]?
    def find_moment_locale: (Array[String] locale_chain, ?timezone_names: bool) -> Array[String]?
    def fallbacks: (String | Symbol locale) -> Array[Symbol]
    def fallback_locale: (String | Symbol locale) -> Symbol?
    def client_json: (Hash[String, untyped] value) -> String
  end
RBS
File.write(File.join(build, 'client-locale-source-proof.json'), JSON.pretty_generate(proof.merge(candidate_sha256: Digest::SHA256.hexdigest(body), transformations: ['Original request-owned translation caches use String-normalized keys', 'Explicit shared deep_merge + replace preserves mutation/identity', 'Delete-only Hash iteration snapshots keys to retain Ruby traversal semantics', 'Existing I18n enter/leave locale protocol preserves ensure restoration', 'Explicit Rails JSON HTML-entity escaping, not a plain JSON substitute', 'Concrete file-backed date lookup is component-only; application must bind live override-aware I18n'])) + "\n")
