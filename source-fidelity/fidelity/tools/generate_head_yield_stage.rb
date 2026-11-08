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
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
context, metadata = FidelitySourcePackage.member(root, 'actionview-8.1.4', 'lib/action_view/context.rb')
_, flow_metadata = FidelitySourcePackage.member(root, 'actionview-8.1.4', 'lib/action_view/flows.rb')
owner = Prism.parse(context).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ModuleNode).first
node = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :_layout_for }
raise 'source layout_for missing' unless node
method = node.slice.sub('def _layout_for(', 'def source_head_layout_for(')
native_method = method.sub('view_flow.get(name).html_safe', 'ActionView::HtmlFragment.new(view_flow.get(name).to_s)')
File.write(File.join(build, 'head_yield_source.rb'), "module SourceHeadLayoutFor\n#{native_method}\nend\n")
File.write(File.join(build, 'original_head_yield_source.rb'), "module OriginalSourceHeadLayoutFor\n#{method}\nend\n")
_, safety_metadata = FidelitySourcePackage.member(root, 'activesupport-8.1.4', 'lib/active_support/core_ext/string/output_safety.rb')
layout, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:app/views/layouts/application.html.erb")
raise 'head yield layout changed' unless status.success? && layout.b == File.binread(File.join(root, 'discourse/app/views/layouts/application.html.erb'))
anchor = '<%= markdown_alternate_link_tag %>'
finish = layout.index(anchor)
raise 'markdown next boundary missing' unless finish
prefix = layout[0, finish + anchor.length].gsub('GlobalSetting.early_hint_header_mode', 'ListHeadImages.configuration.value("early_hint_header_mode")')
code = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, 'native_locale_layout.rb'), "module NativeLocaleApplicationLayout\ndef render_application_layout\n#{code}\nend\nend\n")
File.write(File.join(build, 'head-yield-source-proof.json'), JSON.pretty_generate({pin: pin, framework: [metadata, flow_metadata, safety_metadata], layout_sha256: Digest::SHA256.hexdigest(layout), layout_for_span: {start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}, transformations: ['Original _layout_for body unchanged; native html_safe explicitly constructs a fresh typed copy matching actual String#html_safe even for SafeBuffer inputs', 'Concrete read-after-completed-body head slot binds genuine already-captured head bytes; native typed immutable safe result retains warm read identity', 'Original reference actual OutputFlow.set/get and original SafeBuffer read/return identity', 'Unknown slots, before-body reads and changed late/interleaved head capture explicitly refuse, not claim generic streaming/mutable flow support'], page_accepted: false}) + "\n")
