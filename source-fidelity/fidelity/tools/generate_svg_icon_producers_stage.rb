# frozen_string_literal: true
require 'prism'
require 'yaml'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "SVG producers source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
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
  raise "SVG producer method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {method: name, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
svg = read.call('lib/svg_sprite.rb')
methods = %i[settings_icons objects_setting_icons plugin_icons plugin_icon_sources].to_h { |name| [name, select.call(svg, name).slice] }
all = select.call(svg, :all_icons)
chain = all.body.body.first.block.body.body.first
until chain.is_a?(Prism::CallNode) && chain.name == :merge && chain.arguments.arguments.first.slice == 'group_icons'
  chain = chain.receiver
  raise 'SVG producers source prefix changed' unless chain
end
# Source parsing/loop is retained, not replaced with an empty object-icon result.
validator = read.call('lib/schema_settings_object_validator.rb')
property = Prism.parse(validator).value.statements.body.grep(Prism::ClassNode).first.body.body.grep(Prism::SingletonClassNode).first.body.body.grep(Prism::DefNode).find { |node| node.name == :property_values_of_type }
raise 'SVG property source method missing' unless property
proof[:spans] << {method: 'class.property_values_of_type', sha256: Digest::SHA256.hexdigest(property.slice)}
raw_property = property.slice.sub('def property_values_of_type(', 'def self.property_values_of_type(')
settings = YAML.safe_load(read.call('config/site_settings.yml'), aliases: true).values.reduce({}, :merge)
types_source = read.call('lib/site_settings/type_supervisor.rb')
get_type = select.call(types_source, :get_type).slice
type_hash = select.call(types_source, :type_hash).slice
type_ids = types_source.match(/Enum\.new\((.*?)\n\s*\)/m)[1].scan(/(\w+):\s*(\d+)/).to_h.transform_values(&:to_i)
ids = settings.to_h do |name, declaration|
  declaration = { 'default' => declaration } unless declaration.is_a?(Hash)
  type = declaration['type']
  type ||= 'enum' if declaration.key?('enum')
  type ||= case declaration['default']
  when String then 'string'
  when Integer then 'integer'
  when Float then 'float'
  when TrueClass, FalseClass then 'bool'
  else raise "SVG producer unknown implicit type #{name}"
  end
  [name.to_sym, type_ids.fetch(type)]
end
symbolize = lambda do |value|
  case value
  when Hash then value.to_h { |key, item| [key.to_sym, symbolize.call(item)] }
  when Array then value.map { |item| symbolize.call(item) }
  else value
  end
end
schema = symbolize.call(settings.fetch('dsa_community_rules').fetch('schema'))
registry = read.call('lib/discourse_plugin_registry.rb')
raise 'SVG registry declaration changed' unless registry.include?('define_register :svg_icons, Set') && registry.include?('define_filtered_register :svg_icon_sources')
select.call(registry, :define_register)
select.call(registry, :define_filtered_register)
read.call('lib/site_settings/yaml_loader.rb')
File.write(File.join(build, 'svg_icon_producers_metadata.rb'), <<~RUBY)
  # frozen_string_literal: false
  module SvgIconDeclarations
    TYPE_IDS = #{ids.inspect}
    OBJECT_SCHEMA = #{schema.inspect}
  end
  class SvgIconReadTypes
    def get_type(name)
      SvgSettingsDeclarations::TYPES[SvgIconDeclarations::TYPE_IDS[name.to_sym]]
    end
    def type_hash(name)
      raise ArgumentError, 'unacquired SVG type_hash profile' unless name.to_sym == :dsa_community_rules && get_type(name) == :objects
      {type: 'objects', schema: SvgIconDeclarations::OBJECT_SCHEMA}
    end
  end
  class SvgSourcePropertyWalk
    def initialize(schema:, object:)
      raise ArgumentError, 'nonempty SVG object property walk unacquired'
    end
    #{raw_property.sub('values = Set.new', "objects = [{}] if ENV.fetch('FIDELITY_SVG_PRODUCERS_FAULT', '') == 'nonempty-objects'\n    values = Set.new")}
  end
  class DiscoursePluginRegistry
    def self.svg_icons; @svg_icons ||= Set.new; end
    def self.svg_icon_sources
      @svg_icon_sources ||= Array.new
      raise ArgumentError, 'nonempty SVG icon callbacks unacquired' unless @svg_icon_sources.empty?
      @svg_icon_sources.filter_map { |h| h[:value] if h[:plugin].enabled? }.uniq
    end
  end
RUBY
methods[:settings_icons] = methods[:settings_icons].sub("      site_setting_icons\n", "      site_setting_icons << 'fidelity-wrong-icon' if ENV.fetch('FIDELITY_SVG_PRODUCERS_FAULT', '') == 'wrong-settings'\n      site_setting_icons = [123] if ENV.fetch('FIDELITY_SVG_PRODUCERS_FAULT', '') == 'wrong-type'\n      site_setting_icons\n")
File.write(File.join(build, 'original_svg_icon_producers_metadata.rb'), <<~RUBY)
  class SvgSourcePropertyWalk
    def initialize(schema:, object:); raise ArgumentError, 'nonempty SVG object property walk unacquired'; end
    #{raw_property}
  end
  module OriginalSvgIconDeclarations
    TYPE_IDS = #{ids.inspect}
  end
  class OriginalSvgIconReadTypes
    def self.types; SvgSettingsDeclarations::TYPES; end
    def initialize
      @types = OriginalSvgIconDeclarations::TYPE_IDS
      @schemas = {dsa_community_rules: SvgIconDeclarations::OBJECT_SCHEMA}
      @choices = {}
      @validators = {}
      @allow_any = {}
      @list_type = {}
      @textareas = {}
      @authorized_extensions = {}
      @max_file_size_kb = {}
      @json_schemas = {}
    end
    def get_enum_class(name); raise ArgumentError, 'unacquired SVG enum UI metadata'; end
    def json_schema_class(name); raise ArgumentError, 'unacquired SVG JSON schema metadata'; end
    #{get_type}
    #{type_hash.sub('name = name.to_sym', "name = name.to_sym\n    raise ArgumentError, 'unacquired SVG type_hash profile' unless name == :dsa_community_rules")}
  end
RUBY
candidate = methods.values.join("\n").gsub('get_set_cache(', 'get_set_cache_icons(').gsub('SiteSetting.settings_hash', 'RequestSvgBootstrap.settings_hash').gsub('SiteSetting.type_supervisor', 'SvgIconProducers.types').gsub('SchemaSettingsObjectValidator', 'SvgSourcePropertyWalk').gsub('value.present?', '!ActiveSupport.blank?(value)')
File.write(File.join(build, 'svg_icon_producers_source.rb'), <<~RUBY)
  module RequestSvgSource
    #{candidate}
    def self.all_icons(theme_id = nil)
      get_set_cache_icons("icons_\#{Theme.transform_ids(theme_id).join(',')}") do
        #{chain.slice}
        raise HtmlRenderingBoundary, 'actual SVG settings/plugin/badge/group icons acquired; theme icon acquisition pending'
      end
    end
  end
RUBY
original = %i[settings_icons objects_setting_icons plugin_icons plugin_icon_sources].map { |name| select.call(svg, name).slice }.join("\n").gsub('SiteSetting.type_supervisor', 'SvgIconProducers.types').gsub('SchemaSettingsObjectValidator', 'SvgSourcePropertyWalk')
File.write(File.join(build, 'original_svg_icon_producers_source.rb'), <<~RUBY)
  module OriginalRequestSvgSource
    #{original}
    def self.theme_icons(theme_id)
      raise HtmlRenderingBoundary, 'actual SVG settings/plugin/badge/group icons acquired; theme icon acquisition pending'
    end
  end
RUBY
proof[:transformations] = ['Source settings_icons loop and actual JSON.parse/to_s objects input; original empty objects property walk executed, nonempty constructor explicitly refuses', 'Source get_type and sole objects type_hash projection with all other declaration metadata absent; raw original full type_hash independently executes on source backing metadata, non-objects profiles refuse', 'Existing original define_register/define_filtered_register lazy Set/Array slot specialization; nonempty callback profile refuses, never substituted empty callback output', 'Original badge/group readonly producers and original settings/plugin producer source, actual owned cold publications and warm hits', 'Original all_icons source chain executes through group_icons; both runtimes refuse before unacquired theme icon work, not full bundle/page']
File.write(File.join(build, 'svg-icon-producers-source-proof.json'), JSON.pretty_generate(proof) + "\n")
