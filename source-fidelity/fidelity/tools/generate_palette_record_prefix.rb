# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
app, build = ARGV
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], full_base_palette_acquired: false, page_accepted: false}
read = lambda do |path|
  value, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "palette source changed #{path}" unless status.success? && value.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(value)
  value
end
source = read.call('app/models/color_scheme.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
methods = owner.body.body.grep(Prism::DefNode)
select = lambda do |name|
  nodes = methods.select { |node| node.name == name && node.receiver }
  raise "palette source method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
base = select.call(:base)
colors = select.call(:base_colors)
constants = owner.body.body.grep(Prism::ConstantWriteNode).select { |node| %i[NAMES_TO_ID_MAP LIGHT_PALETTE_NAME].include?(node.name) }
raise 'palette source constants missing' unless constants.size == 2
constructor = base.slice[/scheme = new\([^\n]+\)/] or raise 'palette constructor source changed'
assignment = base.slice[/scheme\.colors = ([^\n]+)/, 1] or raise 'palette colors source changed'
path = File.join(root, 'discourse/app/assets/stylesheets/common/foundation/colors.scss')
read.call('app/assets/stylesheets/common/foundation/colors.scss')
# Only the constructor and SCSS attribute-vector prefix are acquired here.
# The next unsaved collection writer/singleton-name/flags remain unacquired.
text = "module PaletteRecordPrefix\n#{constants.map(&:slice).join("\n")}\nBASE_COLORS_FILE = #{path.dump}\n@mutex = Mutex.new\n#{colors.slice}\ndef self.new(**attrs); ::ColorScheme.new(attrs); end\ndef self.acquire\n#{constructor}\n@record = scheme\n@color_attributes = #{assignment}\nnil\nend\ndef self.record; @record; end\ndef self.color_attributes; @color_attributes; end\nend\n"
raise 'invalid palette prefix source' unless Prism.parse(text).success?
File.write(File.join(build, 'palette_record_prefix_source.rb'), text)
File.write(File.join(build, 'original_palette_record_prefix_source.rb'), text.sub('module PaletteRecordPrefix', 'module OriginalPaletteRecordPrefix'))
File.write(File.join(app, 'app/models/color_scheme.rb'), "class ColorScheme < ActiveRecord::Base\n# remote_copy default is explicitly applied at each admitted scoped lookup.\nend\n")
proof[:adaptations] = ['Actual source new(id/name), real generated ActiveRecord record constructor, no persistence', 'Complete source base_colors Mutex/file/regex/Hash memo uses verified pinned SCSS at runtime', 'Actual next colors= attribute-vector expression evaluated but NOT applied or replaced with fake association target', 'Explicit remote_copy:false default predicate on real ORM lookup; no fake base DBrow', 'Association writer, flags, per-object I18n name and complete stylesheet fallback not yet claimed']
File.write(File.join(build, 'palette-record-prefix-source-proof.json'), JSON.pretty_generate(proof) + "\n")
