# frozen_string_literal: true
# Scope is only source experimental core upcoming Boolean GETTERS, not activation.
require 'prism'
require 'yaml'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:config/site_settings.yml")
raise 'SVG experimental declarations changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/config/site_settings.yml'))
settings = YAML.safe_load(source, aliases: true).fetch('experimental')
names = settings.select do |_, definition|
  definition.is_a?(Hash) && definition['upcoming_change'].is_a?(Hash) &&
    [true, false].include?(definition['default']) &&
    !%w[depends_on depends_on_values plugin themeable enum upcoming_change_default_override mandatory_values].any? { |key| definition.key?(key) }
end.keys
raise 'SVG experimental first source flag changed' unless names.first == 'enable_user_menu_mentions_tab'
shared = File.read(File.join(root, 'fidelity/test/svg_default_context.rb'))
nodes = []
visit = lambda do |node|
  nodes << node if node.is_a?(Prism::DefNode) && node.name == :svg_change_enabled
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(shared).value)
raise 'SVG shared upcoming read method changed' unless nodes.size == 1
File.write(File.join(build, 'svg_experimental_source.rb'), "module SvgExperimentalDeclarations\nNAMES = #{names.inspect}\nend\n")
File.write(File.join(build, 'svg-experimental-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), names: names, shared_method_sha256: Digest::SHA256.hexdigest(nodes.first.slice), transformations: ['Only source-selected experimental core Boolean upcoming getters with no plugin/dependencies/theme/enum/default overrides', 'Reuse existing svg_change_enabled source-matched opt-out/promotion/permanent/default algorithm verbatim; only explicit declaration-name admission union extended, no new generic profile or runtime values', 'Original reference raw UpcomingChanges.enabled? on fresh actual live provider/metadata', 'Other categories/special dependencies keep their already-proved paths; no generic activation or permission-map support'], full_settings_boot: false, page_accepted: false}) + "\n")
