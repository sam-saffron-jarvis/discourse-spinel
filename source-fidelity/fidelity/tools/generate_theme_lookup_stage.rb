# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require_relative 'source_package'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, source: {}, spans: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "Theme lookup source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:source][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |text, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name && (name != :resolve_baked_field || node.receiver.is_a?(Prism::SelfNode))
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(text).value)
  raise "Theme method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
theme = read.call('app/models/theme.rb')
lookup = select.call(theme, :lookup_field).slice
resolve = select.call(theme, :resolve_baked_field).slice
values = select.call(theme, :theme_field_values).slice
field = read.call('app/models/theme_field.rb')
callback = select.call(field, :ensure_baked!)
statements = callback.body.is_a?(Prism::BeginNode) ? callback.body.statements.body : callback.body.body
prefix = statements.first(2).map(&:slice).join("\n")
raise 'bake prefix changed' unless prefix.include?('needs_baking = !value_baked || compiler_version != Theme.compiler_version') && prefix.include?('return unless needs_baking')
placeholder = field.lines.find { |line| line.strip.start_with?('CSP_NONCE_PLACEHOLDER = ') }.strip
raise 'CSP placeholder missing' unless placeholder
model = <<~SOURCE
  class ThemeField < ActiveRecord::Base
    #{placeholder}
    def ensure_baked!
      ThemeFieldReadBootstrap.note_callback
      #{prefix.sub('return unless needs_baking', "raise ArgumentError, 'unowned Theme field rebake PG effects refused before dispatch' if needs_baking || ENV.fetch('FIDELITY_THEME_FIELD_FAULT', '') == 'rebake-required'\nreturn unless needs_baking").gsub('Theme.compiler_version', 'ListThemeCompilerSource.compiler_version')}
    end
  end
SOURCE
File.write(File.join(app, 'app/models/theme_field.rb'), model)
File.write(File.join(app, 'sig/theme_lookup_reads.rbs'), "module ListThemeCompilerSource\n  def self.compiler_version: () -> String\nend\nmodule ThemeFieldReadBootstrap\n  def self.note_callback: () -> nil\nend\n")
native_lookup = lookup.gsub('theme_id.blank?', 'ActiveSupport.blank?(theme_id)').gsub('resolved.html_safe', 'ActionView::HtmlFragment.new(resolved)')
native_lookup = native_lookup.sub('theme_ids = !skip_transformation', "raise ArgumentError, 'array Theme IDs with skip_transformation are unsupported' if skip_transformation && !theme_id.is_a?(Integer)\n    theme_ids = !skip_transformation")
native_lookup = native_lookup.gsub('ThemeField::CSP_NONCE_PLACEHOLDER', '::ThemeField::CSP_NONCE_PLACEHOLDER')
native_resolve = resolve.sub('I18n.fallbacks[name]', 'theme_fallbacks(name)')
calls = []
visit = lambda do |node|
  if node.is_a?(Prism::CallNode) && node.name == :join && node.slice.start_with?('theme_field_values(theme_ids, :translations,')
    calls << node
  else
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
end
visit.call(Prism.parse(native_resolve).value)
raise 'translation resolver expression ambiguous' unless calls.size == 1
anchor = calls.first.slice
raise 'translation resolver shape changed' unless native_resolve.include?(anchor)
native_resolve = native_resolve.sub(anchor, <<~'SOURCE'.strip)
  pairs = theme_field_values(theme_ids, :translations, theme_fallbacks(name))
      seen = []
      result = []
      pairs.each do |tuple, items|
        id = tuple[0]
        raise TypeError, 'Theme tuple identity not Integer' unless id.is_a?(Integer)
        if items && !seen.include?(id)
          seen << id
          result.concat(items)
        end
      end
      result.join("\n")
SOURCE
values = values.sub('.map { |tf| [[tf.theme_id', '.map { |tf| ThemeFieldReadBootstrap.note_read_row; [[tf.theme_id')
native_values = values.gsub('x.map(&:second)', 'x.map { |pair| pair[1] }').gsub('Theme.compiler_version', 'ListThemeCompilerSource.compiler_version').gsub('Theme.targets', 'ListThemeArraySource::TARGETS')
native_values = native_values.sub('.each(&:ensure_baked!)', '.each { |tf| tf.ensure_baked! unless ENV.fetch("FIDELITY_THEME_FIELD_FAULT", "") == "omit-callback" }')
native_values = native_values.sub('keys = keys.map', 'ThemeFieldReadBootstrap.note_keys(keys); keys = keys.map')
values = values.sub('keys = keys.map', 'ThemeFieldReadBootstrap.note_keys(keys); keys = keys.map').sub('cache.defer_get_set_bulk(', 'cache.defer_get_set_fields(')
native_values = native_values.sub('cache.defer_get_set_bulk(', 'cache = CategoryCacheBootstrap.theme_compiler_cache\n    cache.defer_get_set_fields('.gsub('\\n', "\n"))
File.write(File.join(build, 'theme_lookup_source.rb'), <<~SOURCE)
  module ListThemeCompilerSource
    def self.theme_fallbacks(locale)
      current_root = RequestClientLocaleBootstrap.root
      raise 'actual client locale root missing' unless current_root.is_a?(String)
      RequestClientLocaleSource.new(current_root, RequestAssetEnvironment.new(ENV.fetch('RAILS_ENV'))).fallbacks(locale)
    end
    #{native_lookup}
    #{native_resolve}
    #{native_values}
  end
SOURCE
File.write(File.join(build, 'original_theme_lookup_source.rb'), <<~SOURCE)
  module OriginalThemeLookupSource
    Theme = ListThemeCompilerSource
    I18n = OriginalClientLocaleI18n
    def self.cache; CategoryCacheBootstrap.theme_compiler_cache; end
    def self.transform_ids(ids); ::Theme.transform_ids(ids); end
    #{lookup}
    #{resolve}
    #{values}
  end
  module OriginalThemeFieldCallback
    Theme = ListThemeCompilerSource
    #{callback.slice}
  end
SOURCE
helper = select.call(read.call('app/helpers/application_helper.rb'), :theme_translations_lookup).slice
native_helper = helper.gsub('Theme.lookup_field(', 'ListThemeCompilerSource.lookup_field(').gsub('request.env[:skip_theme_ids_transformation].present?', 'ActiveSupport.present?(request.env["skip_theme_ids_transformation"])')
File.write(File.join(build, 'theme_lookup_helpers.rb'), "module ThemeLookupHelpers\n#{native_helper.sub('def theme_translations_lookup', 'def source_theme_translations_lookup')}\nend\n")
original_path = File.join(build, 'original_theme_lookup_source.rb')
File.write(original_path, File.read(original_path) + "\nmodule OriginalThemeLookupHelpers\nTheme = OriginalThemeLookupSource\n#{helper.sub('def theme_translations_lookup', 'def original_theme_translations_lookup')}\nend\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = "<%= preload_script 'js/browser-detect' %>"
finish = layout.index(anchor)
raise 'next core preload boundary changed' unless finish
partial = layout[0, finish + anchor.length].gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(partial, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
%w[theme_lookup_source.rb original_theme_lookup_source.rb theme_lookup_helpers.rb native_locale_layout.rb].each do |file|
  parsed = Prism.parse_file(File.join(build, file))
  raise "invalid Theme source #{file}: #{parsed.errors.map(&:message)}" unless parsed.success?
end
proof[:framework] = %w[lib/active_support/core_ext/array/access.rb lib/active_support/core_ext/string/access.rb].map { |member| FidelitySourcePackage.member(root, 'activesupport-8.1.4', member)[1] }
proof[:transformations] = ['Exact source Theme field relation chain/or/callback/group/order retained', 'Separate typed field bulk entrypoint uses same original acquired cache', 'Translation select/uniq(theme identity)/flat_map expanded without changing tuple order or nil-vs-empty selection', 'Original ensure_baked! prefix runs for every actual row; needs_baking refuses BEFORE writes; reference invokes full original method on admitted current rows', 'Native source HtmlSafe result represented by typed HtmlFragment; original helper/reference retains html_safe', 'Actual template through browser-update Propshaft URL; next browser-detect preload refuses']
File.write(File.join(build, 'theme-lookup-source-proof.json'), JSON.pretty_generate(proof) + "\n")
