# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
shared = File.read(File.join(root, 'fidelity/test/markdown_setting_context.rb'))
nodes = []
visit = lambda do |node|
  nodes << node if node.is_a?(Prism::DefNode) && node.name == :get_markdown_endpoints_for_layout
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(shared).value)
raise 'shared source upcoming reader ambiguous' unless nodes.size == 1
profile = ARGV[1]
raise 'unsupported simple SVG upcoming getter profile' unless profile.nil? || profile == 'media-convert'
field = profile ? 'composer_media_optimization_image_convert_enabled' : 'remove_and_replace_uncategorized'
method = profile ? 'get_svg_media_convert_change' : 'get_svg_uncategorized_change'
prefix = profile ? 'svg_media_convert' : 'svg_uncategorized'
body = nodes.first.slice.gsub('get_markdown_endpoints_for_layout', method).gsub('enable_markdown_endpoints', field).gsub('markdown', profile ? 'SVG media-convert' : 'SVG uncategorized')
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:lib/upcoming_changes.rb")
raise 'uncategorized upcoming source changed' unless status.success? && source.b == File.binread(File.join(root, 'discourse/lib/upcoming_changes.rb'))
File.write(File.join(build, prefix + '_source.rb'), "module SiteSettings\nclass PortableReadStore\n#{body}\nend\nend\n")
File.write(File.join(build, prefix.tr('_', '-') + '-source-proof.json'), JSON.pretty_generate({pin: pin, setting: field, original_upcoming_sha256: Digest::SHA256.hexdigest(source), reused_shared_method_sha256: Digest::SHA256.hexdigest(nodes.first.slice), transformations: ['Reuse already source-matched strict no-plugin/no-dependency Boolean promotion algorithm with exact declaration-name substitution only', 'Getter only; no toggle/setter/action/migration invoked', 'Original reference raw UpcomingChanges.enabled? independent of candidate Boolean'], full_settings_boot: false, pg_writes: false, page_accepted: false}) + "\n")
