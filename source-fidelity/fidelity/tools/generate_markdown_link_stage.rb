# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require 'action_view'
require 'action_view/template/handlers/erb/erubi'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
app = ARGV.fetch(1)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "markdown source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  source
end
source = read.call('lib/markdown_endpoint/controller_support.rb')
nodes = []
constant = nil
visit = lambda do |node|
  nodes << node if node.is_a?(Prism::DefNode) && %i[markdown_alternate_link_tag markdown_alternate_url markdown_alternate_path].include?(node.name)
  constant = node if node.is_a?(Prism::ConstantWriteNode) && node.name == :SAFE_QUERY_PARAMETERS
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(source).value)
raise 'markdown source ambiguity' unless nodes.size == 3 && constant
safe_array = constant.value
safe_array = safe_array.receiver if safe_array.is_a?(Prism::CallNode) && safe_array.name == :freeze
raise 'markdown safe query declaration changed' unless safe_array.is_a?(Prism::ArrayNode)
link = nodes.find { |n| n.name == :markdown_alternate_link_tag }
url = nodes.find { |n| n.name == :markdown_alternate_url }
path = nodes.find { |n| n.name == :markdown_alternate_path }
native_link = link.slice.sub('def markdown_alternate_link_tag', 'def source_markdown_alternate_link_tag').gsub('request.format.md?', 'controller.request_format == :md').gsub('url.blank?', 'ActiveSupport.blank?(url)').sub('helpers.tag.link(', 'source_markdown_void_link(')
native_url = url.slice.sub('def markdown_alternate_url', 'def source_markdown_alternate_url').gsub('path.blank?', 'ActiveSupport.blank?(path)').gsub('query.present?', 'ActiveSupport.present?(query)').gsub('query.to_query', 'markdown_query_string(query)').sub('request.query_parameters.slice(*SAFE_QUERY_PARAMETERS)', 'request.query_parameters.select { |key, _value| SAFE_QUERY_PARAMETERS.include?(key) }')
native_path = path.slice.gsub('app_path.blank?', 'ActiveSupport.blank?(app_path)')
File.write(File.join(build, 'markdown_link_helpers.rb'), <<~RUBY)
  require 'cgi'
  module MarkdownLinkHelpers
    #{constant.slice}
    #{native_link}
    #{native_url}
    #{native_path}
    def controller_name; controller.controller_name; end
    def action_name; controller.action_name; end
    def markdown_query_string(query)
      # Exact AS Hash/Object#to_query scalar String profile; parsed nested
      # arrays/hashes explicitly refuse rather than stringify incorrectly.
      encoded = []
      query.each do |key, value|
        raise ArgumentError, 'unsupported nested markdown query profile' unless key.is_a?(String) && value.is_a?(String)
        encoded << CGI.escape(key) + '=' + CGI.escape(value)
      end
      encoded.sort.join('&')
    end
    def source_markdown_void_link(rel:, type:, href:)
      raise TypeError, 'markdown link attributes must be Strings' unless rel.is_a?(String) && type.is_a?(String) && href.is_a?(String)
      href += '#wrong' if ENV.fetch('FIDELITY_MARKDOWN_FAULT', '') == 'wrong-href'
      ActionView::HtmlFragment.new('<link' + ActionView::ViewHelpers.tag_attr('rel', rel) + ActionView::ViewHelpers.tag_attr('type', type) + ActionView::ViewHelpers.tag_attr('href', href) + '>')
    end
  end
RUBY
original_link = link.slice.sub('def markdown_alternate_link_tag', 'def source_markdown_alternate_link_tag').sub('request.format.md?', 'Mime[controller.request_format].md?')
original_url = url.slice.sub('def markdown_alternate_url', 'def source_markdown_alternate_url')
File.write(File.join(build, 'original_markdown_link_helpers.rb'), <<~RUBY)
  require 'active_support/core_ext/object/to_query'
  require 'action_view/helpers/tag_helper'
  class OriginalMarkdownTagCarrier
    include ActionView::Helpers::TagHelper
  end
  module OriginalMarkdownLinkHelpers
    #{constant.slice}
    #{original_link}
    #{original_url}
    #{path.slice}
    def controller_name; controller.controller_name; end
    def action_name; controller.action_name; end
    def helpers; @markdown_tag_carrier ||= OriginalMarkdownTagCarrier.new; end
  end
RUBY
# The original catalog/config guard remains authoritative. Expand ONLY the
# already-source-declared modifier accessor dispatch, preserving custom getters.
structure = read.call('db/structure.sql')
columns = structure.match(/^CREATE TABLE public\.theme_modifier_sets \(\n(.*?)^\);/m)
raise 'modifier source declaration missing' unless columns
names = columns[1].lines.filter_map { |line| line[/^    ([a-z_]+) /, 1] } - %w[id theme_id theme_setting_modifiers]
raise 'empty modifier source declarations' if names.empty?
model_path = File.join(app, 'app/models/theme_modifier_set.rb')
model = File.read(model_path)
old = '.map { |s| s.public_send(modifier_name) }'
raise 'modifier dispatch source changed' unless model.scan(old).size == 1
model = model.sub(old, '.map { |s| s.source_declared_modifier_value(modifier_name) }')
getter = "def source_declared_modifier_value(name)\ncase name\n" + names.map { |name| "when :#{name} then self.#{name}" }.join("\n") + "\nelse\nraise ArgumentError, 'unsupported undeclared Theme modifier accessor'\nend\nend\n"
File.write(model_path, model.sub(/end\s*\z/, getter + "end\n"))
modifier_source = read.call('app/models/theme_modifier_set.rb')
modifier_owner = Prism.parse(modifier_source).value.statements.body.grep(Prism::ClassNode).first
modifier_method = modifier_owner.body.body.grep(Prism::DefNode).find { |n| n.name == :resolve_modifier_for_themes && n.receiver }
raise 'original modifier resolver missing' unless modifier_method
original_method = modifier_method.slice.sub('def self.', 'def ')
File.write(File.join(build, 'original_markdown_modifier_dispatch.rb'), "module OriginalMarkdownModifierDispatch\nThemeModifierSetError = ::ThemeModifierSet::ThemeModifierSetError\n#{original_method}\nend\nThemeModifierSet.singleton_class.send(:define_method, :resolve_modifier_for_themes, OriginalMarkdownModifierDispatch.instance_method(:resolve_modifier_for_themes))\n")
layout = read.call('app/views/layouts/application.html.erb')
anchor = '<%= tag.meta id: \'data-discourse-setup\', data: client_side_setup_data %>'
finish = layout.index(anchor)
raise 'client setup boundary missing' unless finish
prefix = layout[0, finish + anchor.length].gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
_, query_metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/core_ext/object/to_query.rb')
_, tag_metadata = FidelitySourcePackage.member(root, 'actionview-8.1.4', 'lib/action_view/helpers/tag_helper.rb')
File.write(File.join(build, 'markdown-link-source-proof.json'), JSON.pretty_generate({pin: pin, source_sha256: Digest::SHA256.hexdigest(source), modifier_structure_sha256: Digest::SHA256.hexdigest(structure), bounded_modifier_accessors: names, modifier_resolver_source_sha256: Digest::SHA256.hexdigest(modifier_source), modifier_resolver_span: {start: modifier_method.location.start_offset, end: modifier_method.location.end_offset, sha256: Digest::SHA256.hexdigest(modifier_method.slice)}, setting_extension_sha256: Digest::SHA256.hexdigest(read.call('lib/site_setting_extension.rb')), upcoming_changes_sha256: Digest::SHA256.hexdigest(read.call('lib/upcoming_changes.rb')), framework: [query_metadata, tag_metadata], safe_query_keys: safe_array.elements.map(&:unescaped), spans: nodes.map { |n| {method: n.name, start: n.location.start_offset, end: n.location.end_offset, sha256: Digest::SHA256.hexdigest(n.slice)} }, transformations: ['Exact source feature/path/route/query selection; real typed request format maps to original MIME predicate', 'Actual query Hash populated from original same parser BEFORE path-parameter merge', 'AS scalar String query sorting + exact CGI per-byte encoding; nested profiles refuse', 'Concrete void link binds existing typed attribute escaping; original actual TagHelper/Hash#to_query reference retained', 'One concrete upcoming getter uses live opt-out/promotion/permanent/default, raw original UpcomingChanges reference; not generic settings declaration acceptance', 'Actual plugin before-head-close helper executes; next no-arg tag builder refuses'], page_accepted: false}) + "\n")
