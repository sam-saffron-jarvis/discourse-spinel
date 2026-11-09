# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, full_base_palette_acquired: false, page_accepted: false}
read = lambda do |path|
  value, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "base palette source changed #{path}" unless status.success? && value.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(value)
  value
end
source = read.call('app/models/color_scheme.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
select = lambda do |name|
  nodes = owner.body.body.grep(Prism::DefNode).select { |node| node.name == name && (name == :colors= ? node.receiver.nil? : !node.receiver.nil?) }
  raise "base palette method ambiguous #{name}" unless nodes.size == 1
  nodes.first.slice
end
base = select.call(:base)
writer = select.call(:colors=)
name_block = 'scheme.define_singleton_method(:name) do' + "\n          I18n.t(\"admin_js.admin.customize.theme.default_light_scheme\")\n        end"
raise 'base palette name override changed' unless base.scan(name_block).size == 1
native = base.sub(name_block, 'scheme.source_base_palette_name!')
common = <<~RUBY
  NAMES_TO_ID_MAP = PaletteRecordPrefix::NAMES_TO_ID_MAP
  LIGHT_PALETTE_NAME = PaletteRecordPrefix::LIGHT_PALETTE_NAME
  def self.new(**attrs); PaletteBaseRead.build_record(attrs); end
  def self.base_colors; PaletteRecordPrefix.base_colors; end
RUBY
File.write(File.join(build, 'palette_base_source.rb'), "module PaletteBaseSource\n#{common}\n#{native}\nend\n")
File.write(File.join(build, 'original_palette_base_source.rb'), "module OriginalPaletteBaseSource\n#{common}\n#{base}\nend\n")
# The source mutator constructs real unsaved records. Its collection append is
# bound only to this unsaved owner domain; child FK stays nil, no save path.
writer = writer.sub('color_scheme_colors << ColorSchemeColor.new(name: c[:name], hex: c[:hex])', 'append_unsaved_base_color(ColorSchemeColor.new(name: c[:name], hex: c[:hex]))')
File.write(File.join(app, 'app/models/color_scheme.rb'), <<~RUBY)
  class ColorScheme < ActiveRecord::Base
    attr_accessor :is_base, :is_builtin_default
    #{writer}
    def source_base_palette_name!; @source_base_palette_name = true; nil; end
    def source_base_palette_name_off!; @source_base_palette_name = false; nil; end
    def name
      @source_base_palette_name ? I18n.t('admin_js.admin.customize.theme.default_light_scheme') : @name
    end
    def source_raw_palette_name; @name; end
    def source_unsaved_base_colors; @source_unsaved_base_colors ||= []; end
    def append_unsaved_base_color(color)
      raise ArgumentError, 'unsupported persisted palette collection write' unless new_record? && color.new_record?
      color.source_attach_base_palette(self)
      source_unsaved_base_colors << color
      self
    end
  end
RUBY
color = read.call('app/models/color_scheme_color.rb')
File.write(File.join(app, 'app/models/color_scheme_color.rb'), <<~RUBY)
  class ColorSchemeColor < ActiveRecord::Base
    def id; new_record? ? nil : @id; end
    def source_attach_base_palette(owner)
      raise ArgumentError, 'unsupported persisted palette child attachment' unless new_record? && owner.new_record?
      # Raw AR unsaved-owner concat leaves the foreign key nil until persistence.
      @source_base_palette_owner = owner
      nil
    end
    def source_base_palette_owner; @source_base_palette_owner; end
  end
RUBY
%w[en fr].each do |locale|
  relative = "config/locales/client.#{locale}.yml"
  text = read.call(relative)
  destination = File.join(app, "config/locales/palette_client.#{locale}.yml")
  File.write(destination, text)
end
# Pure raw ActiveRecord reference: no Rails application, query/list/HTML request,
# plugin activation, save/create, cache compiler or writer is invoked.
constants = owner.body.body.grep(Prism::ConstantWriteNode).select { |node| %i[NAMES_TO_ID_MAP LIGHT_PALETTE_NAME].include?(node.name) }.map(&:slice).join("\n")
base_colors = select.call(:base_colors)
scss = File.join(root, 'discourse/app/assets/stylesheets/common/foundation/colors.scss')
raw_writer = select.call(:colors=)
raw_has_many = owner.body.body.grep(Prism::CallNode).find { |node| node.name == :has_many && node.arguments.arguments.first.slice == ':color_scheme_colors' }
raise 'raw base palette has_many missing' unless raw_has_many
reference = <<~RUBY
  require 'active_record'
  require 'i18n'
  require 'json'
  require #{File.join(root, 'fidelity/tools/oracle_isolation.rb').dump}
  raise 'palette reference PG endpoint' unless ENV.fetch('DATABASE_URL') == 'postgres://discourse@127.0.0.1:5499/discourse_development'
  raise 'palette reference PG readonly' unless ENV.fetch('PGOPTIONS').include?('default_transaction_read_only=on')
  I18n.load_path += #{%w[en fr].map { |locale| File.join(root, "discourse/config/locales/client.#{locale}.yml") }.inspect}
  class ColorScheme < ActiveRecord::Base
    #{constants}
    BASE_COLORS_FILE = #{scss.dump}
    @mutex = Mutex.new
    attr_accessor :is_base, :is_builtin_default
    default_scope { where(remote_copy: false) }
    #{raw_has_many.slice}
    #{base_colors}
    #{base}
    #{raw_writer}
  end
  class ColorSchemeColor < ActiveRecord::Base
    belongs_to :color_scheme, -> { unscope(where: :remote_copy) }
  end
  ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
  begin
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      raise 'raw palette pool writable' unless connection.select_value('SHOW default_transaction_read_only') == 'on'
      scheme = ColorScheme.base
      names = %w[en fr].map { |locale| I18n.with_locale(locale) { scheme.name } }
      records = scheme.color_scheme_colors.to_a
      raise 'raw palette unexpectedly persisted' unless scheme.new_record? && records.all?(&:new_record?)
      puts 'FIDELITY_RAW_PALETTE_BASE ' + JSON.generate({id: scheme.id, raw_name: scheme.read_attribute(:name), version: scheme.version, via_wizard: scheme.via_wizard, user_selectable: scheme.user_selectable, remote_copy: scheme.remote_copy, names: names, new_record: scheme.new_record?, persisted: scheme.persisted?, is_base: scheme.is_base, is_builtin_default: scheme.is_builtin_default, colors: records.map { |c| {id: c.id, name: c.name, hex: c.hex, color_scheme_id: c.color_scheme_id, new_record: c.new_record?, persisted: c.persisted?} }, memo_identity: scheme.equal?(ColorScheme.base)})
    end
  ensure
    ActiveRecord::Base.connection_pool.disconnect!
  end
RUBY
File.write(File.join(build, 'raw_palette_base_reference.rb'), reference)
proof[:adaptations] = ['Complete actual base factory/SCSS and colors= loop, genuine unsaved ActiveRecord records, no fake DBrow or save', 'Source collection << specialized only for unsaved owner/child, actual nil child FK and private ownership reference; generic association inverse/proxy API not acquired', 'Per-object singleton name lowered to private per-instance flag plus class method; raw field stays unchanged and other instances unaffected; generic singleton reflection API unclaimed', 'Full immutable en/fr client YAML resources compiled through existing application I18n, not captured getter outputs', 'Independent raw ActiveRecord gem model/has_many writer/base singleton method with same PG readonly guards, no Rails application/HTML bootstrap']
File.write(File.join(build, 'palette-base-source-proof.json'), JSON.pretty_generate(proof) + "\n")
