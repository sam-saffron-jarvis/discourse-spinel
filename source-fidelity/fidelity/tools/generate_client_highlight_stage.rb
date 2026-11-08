# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "client path source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "client path method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
helper = read.call('app/helpers/application_helper.rb')
admin = select.call(helper, :loading_admin?).slice.sub('def loading_admin?', 'def source_loading_admin?')
File.write(File.join(build, 'client_loading_admin_source.rb'), "module ClientLoadingAdminSource\n#{admin.gsub('controller.class.name.blank?', 'ActiveSupport.blank?(controller.class.name)')}\nend\n")
File.write(File.join(build, 'original_client_loading_admin_source.rb'), "module OriginalClientLoadingAdminSource\n#{admin}\nend\n")
highlight = read.call('lib/highlight_js.rb')
proof[:highlight_version] = Prism.parse(highlight).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ConstantWriteNode).find { |n| n.name == :VERSION }.value.value
vendor = read.call('lib/vendored_assets.rb')
raise 'highlight vendor path changed' unless vendor.include?('DIRECTORY = "vendor/runtime_node_modules"') && vendor.include?('Rails.root.join(DIRECTORY, relative_path)')
read.call('script/copy_vendored_assets.mjs')
read.call('pnpm-lock.yaml')
native = highlight.sub('module HighlightJs', 'module RequestHighlightJs').gsub('VendoredAssets.path(', 'ClientHighlightBootstrap.vendored_path(').gsub('File.read(languages_dir + "#{lang}.min.js")', 'ClientHighlightBootstrap.read_language(languages_dir + "#{lang}.min.js")').gsub('GlobalSetting.asset_url_salt', 'ClientHighlightBootstrap.asset_url_salt')
native = native.sub('module RequestHighlightJs', "module RequestHighlightJs\nRailsMultisite = CategoryCacheApplication::RailsMultisite")
original = highlight.sub('module HighlightJs', <<~RUBY.chomp)
  module OriginalRequestHighlightJs
    RailsMultisite = OriginalCategoryCacheApplication::RailsMultisite
    module VendoredAssets
      def self.path(relative); ClientHighlightBootstrap.vendored_path(relative); end
    end
    module GlobalSetting
      def self.asset_url_salt; ClientHighlightBootstrap.asset_url_salt; end
    end
    module File
      def self.read(path); ClientHighlightBootstrap.read_language(path); end
    end
RUBY
File.write(File.join(build, 'client_highlight_source.rb'), native)
File.write(File.join(build, 'original_client_highlight_source.rb'), original)
# Extend the original initial Hash only through the next precise refusal. Never
# return a partial setup Hash or substitute a value for the pending SVG path.
node = select.call(helper, :client_side_setup_data)
entries = node.body.body.first.value.elements
raise 'client path input order changed' unless entries.first(11).map { |e| e.key.unescaped } == %w[cdn base_url base_uri environment letter_avatar_version service_worker_url default_locale asset_version disable_custom_css highlight_js_path svg_sprite_path]
parts = entries.first(11).map.with_index do |entry, i|
  value = entry.value.slice
  value = value.sub('Rails.configuration.action_controller.asset_host', 'settings.asset_host').sub('Rails.env', "ENV.fetch('RAILS_ENV')").sub('LetterAvatar.version', 'PortableLetterAvatarVersion.version').sub('Discourse.assets_digest', 'ClientSetupReadBootstrap.asset_version').sub('HighlightJs.path', 'ClientHighlightBootstrap.path').sub('SvgSprite.path(theme_id)', 'client_setup_svg_path(theme_id)')
  value = "ClientSetupReadBootstrap.record_input(:#{entry.key.unescaped}, (#{value}))" if i < 8
  "#{entry.key.slice} #{value}"
end
File.write(File.join(build, 'client_highlight_setup_source.rb'), "module ClientSetupPrefixSource\ndef source_client_side_setup_data\nsetup_data = {\n#{parts.join(",\n")}\n}\nraise 'client setup SVG boundary unexpectedly returned'\nend\nend\n")
proof[:transformations] = ['Actual loading_admin? on the owned live controller; original source reference retains defined?/blank?/class-name behavior', 'Complete original HighlightJs module, actual live setting/site/salt/hostname and source memo behavior', 'Explicit SAME serving-root vendor path; immutable per-member provenance checked before actual File.read, original ENOENT rescue retained', 'Source initial Hash extends through disable_custom_css/highlight_js_path then explicit SVG refusal; no partial setup returned']
File.write(File.join(build, 'client-highlight-source-proof.json'), JSON.pretty_generate(proof) + "\n")
