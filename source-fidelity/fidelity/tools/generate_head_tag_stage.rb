# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, source: {}, spans: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "head_tag source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, 'discourse', path))
  proof[:source][path] = Digest::SHA256.hexdigest(text)
  text
end
source = read.call('app/helpers/application_helper.rb')
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :theme_lookup }
raise 'actual theme_lookup helper missing' unless node
proof[:spans] << {method: node.name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
original = node.slice.sub('def theme_lookup(', 'def source_head_tag_lookup(')
native = original.gsub('Theme.lookup_field(', 'ListThemeCompilerSource.lookup_field(').gsub('request.env[:skip_theme_ids_transformation].present?', 'ActiveSupport.present?(request.env["skip_theme_ids_transformation"])')
File.write(File.join(build, 'head_tag_helpers.rb'), "module HeadTagHelpers\n#{native}\nend\n")
File.write(File.join(build, 'original_head_tag_helpers.rb'), "module OriginalHeadTagHelpers\nTheme = OriginalThemeLookupSource\n#{original}\nend\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = '<%= render_google_tag_manager_head_code %>'
finish = layout.index(anchor)
raise 'next analytics boundary missing' unless finish
prefix = layout[0, finish + anchor.length].gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
proof[:transformations] = ['Actual source theme_lookup with original mobile predicate and common/desktop field resolution', 'Known head_tag field domain only; source String name converts to Symbol before tuple product', 'Source two-key bulk nil publication verified per missing member, not per queued job', 'Next actual analytics helper explicitly refuses']
File.write(File.join(build, 'head-tag-source-proof.json'), JSON.pretty_generate(proof) + "\n")
