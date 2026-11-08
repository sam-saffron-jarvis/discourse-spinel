# frozen_string_literal: true
# Exact body/template execution order and write-free source prefix only.
require "prism"
require "json"
require "digest"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
app, build = ARGV
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
inputs = {}
spans = []
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "original template input changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  inputs[path] = Digest::SHA256.hexdigest(text)
  text
end
method = lambda do |path, name, singleton = nil|
  found = []
  visit = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name && (singleton.nil? || !node.receiver.nil? == singleton)
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(read.call(path)).value)
  raise "template method span changed #{path}:#{name}" unless found.length == 1
  node = found.first
  spans << {source: path, name: name, start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
message_member = Dir.glob(File.join(root, "run/bundle/ruby/4.0.0/gems/message_bus-*/lib/message_bus/distributed_cache.rb")).fetch(0)
message_gem = message_member.split("/gems/").last.split("/").first
_message_bytes, message_proof = FidelitySourcePackage.member(root, message_gem, "lib/message_bus/distributed_cache.rb")
framework = {}
%w[lib/action_view/renderer/template_renderer.rb lib/action_view/buffers.rb lib/action_view/template/handlers/erb/erubi.rb].each do |member|
  bytes, proof = FidelitySourcePackage.member(root, "actionview-8.1.4", member)
  framework[member] = proof.merge(bytes: bytes)
end
renderer_source = framework.fetch("lib/action_view/renderer/template_renderer.rb")[:bytes]
renderer_methods = []
walk_renderer = lambda do |node|
  renderer_methods << node.slice if node.is_a?(Prism::DefNode) && %i[render_template render_with_layout].include?(node.name)
  node.compact_child_nodes.each { |child| walk_renderer.call(child) }
end
walk_renderer.call(Prism.parse(renderer_source).value)
raise "original renderer sequence changed" unless renderer_methods.length == 2 && renderer_source.include?('view.view_flow.set(:layout, yield(layout))')
template = read.call("app/views/list/list.erb")
layout = read.call("app/views/layouts/application.html.erb")
read.call("lib/distributed_cache.rb")
read.call("lib/scheduler/defer.rb")
method.call("app/models/category.rb", :url, false)
compiled = ActionView::Template::Handlers::ERB::Erubi.new(template, escape: false, trim: true).src
wrapped = "def render_list_body\n#{compiled}\nend"
path_to_target = nil
walk = lambda do |node, parents|
  if node.is_a?(Prism::CallNode) && node.name == :append= && node.slice.include?("t.category.url")
    raise "multiple first category expressions" if path_to_target
    path_to_target = [*parents, node]
  end
  node.compact_child_nodes.each { |child| walk.call(child, [*parents, node]) } unless path_to_target
end
walk.call(Prism.parse(wrapped).value, [])
raise "first body cache call changed" unless path_to_target
node = path_to_target.last
prefix = wrapped[0...node.location.start_offset]
prefix += "@output_buffer.append=(category_url_capability(t.category))\nraise 'category capability unexpectedly returned'\n"
# Close only scopes open at the cut. Every alternate path refuses explicitly;
# no body remainder is represented as rendered or silently omitted.
path_to_target[0...-1].reverse_each do |parent|
  if parent.is_a?(Prism::IfNode)
    prefix += "end\nraise ArgumentError, 'unsupported template-prefix branch without category link'\n"
  elsif parent.is_a?(Prism::BlockNode)
    prefix += "end\nraise ArgumentError, 'unsupported template-prefix empty topic list'\n"
  end
end
prefix += "end\n"
raise "invalid source prefix" unless Prism.parse(prefix).success?
# Original /latest has no category/tag callbacks. Verify actual assignments at
# runtime and reject other profiles; prune only those structurally nil branches.
pruned = []
visitor = lambda do |n|
  if n.is_a?(Prism::IfNode) && ["SiteSetting.tagging_enabled && @tag_name", "@category"].include?(n.predicate.slice)
    pruned << n
  else
    n.compact_child_nodes.each { |child| visitor.call(child) }
  end
end
visitor.call(Prism.parse(prefix).value)
pruned.sort_by { |n| -n.location.start_offset }.each { |n| prefix[n.location.start_offset, n.location.length] = "nil" }
# The prefix has only ordinary String/Integer expressions. A private accumulator
# uses the shared ERB escaping primitive; no new generic renderer is introduced.
crawler_helper = method.call("app/helpers/application_helper.rb", :include_crawler_content?)
original_crawler_helper = crawler_helper.dup
crawler_if = Prism.parse(crawler_helper).value.statements.body.first.body.body.first
raise "crawler helper source profile changed" unless crawler_if.is_a?(Prism::IfNode) && crawler_if.predicate.slice == "current_user && !crawler_layout?"
crawler_helper = "def include_crawler_content?\nraise ArgumentError, 'unsupported authenticated template profile' unless current_user.nil?\n#{crawler_if.subsequent.statements.slice}\nend"
plugin_helper = method.call("app/helpers/application_helper.rb", :server_plugin_outlet)
plugin_first = Prism.parse(plugin_helper).value.statements.body.first.body.body.first.slice
raise "plugin outlet first guard changed" unless plugin_first == 'return "" if !GlobalSetting.load_plugins?'
File.write(File.join(build, "original_template_helpers.rb"), "module OriginalTemplateApplicationHelpers\n#{original_crawler_helper}\n#{plugin_helper}\nend\n")
helper_code = "#{crawler_helper}\ndef server_plugin_outlet(name, locals: {})\n#{plugin_first}\nraise ArgumentError, 'unsupported plugin template profile'\nend\n"
native = "module PortableListBodyPrefix\n#{prefix}\n#{helper_code}\nend\n"
File.write(File.join(build, "list_body_prefix.rb"), native)
File.write(File.join(build, "original_list_body.rb"), "module OriginalListBody\ndef render_list_body\n@output_buffer = ActionView::OutputBuffer.new\n#{compiled}\nend\nend\n")
File.write(File.join(build, "original_renderer_sequence.rb"), "module OriginalRendererSequence\n#{renderer_methods.join("\n")}\nend\n")
File.write(File.join(build, "source_renderer_sequence.rb"), "module SourceRendererSequence\n#{renderer_methods.join("\n")}\nend\n")
# Required original data/URL methods, not replacement application SQL or values.
append_to_owner = lambda do |relative, text|
  path = File.join(app, relative)
  File.write(path, File.read(path).sub(/end\s*\z/) { "#{text}\nend\n" })
end

append_to_owner.call("app/models/category.rb", method.call("app/models/category.rb", :uncategorized?))
global_methods = %i[load_plugins? load_plugins_filter].map { |name| method.call("app/models/global_setting.rb", name, true) }
File.write(File.join(app, "app/models/global_setting_template_reads.rb"), "class GlobalSetting\n#{global_methods.join("\n")}\nend\n")
File.write(File.join(build, "original_category_url.rb"), "module OriginalCategoryUrl\n#{method.call("app/models/category.rb", :url, false)}\nend\n")
urls = [method.call("app/models/topic.rb", :url, true), method.call("app/models/topic.rb", :url, false)]
urls[1] = urls[1].sub("def url(post_number = nil)", "def url(post_number = nil)\nraise HtmlRenderingBoundary, 'Topic#slug would require mutation capability' if read_attribute(:slug).nil?")
append_to_owner.call("app/models/topic.rb", urls.join("\n"))
discourse_methods = %i[base_protocol current_hostname_with_port base_url_no_prefix base_url].map { |name| method.call("lib/discourse.rb", name, true) }
method.call("lib/discourse.rb", :current_hostname, true)
method.call("lib/discourse.rb", :base_path, true)
discourse_methods << "def self.current_hostname\nSiteSetting.force_hostname.presence || SiteSetting.portable_rendering_hostname\nend"
discourse_methods << "def self.base_path(default_value = '')\nSiteSetting.portable_rendering_base_path.presence || default_value\nend"
append_to_owner.call("app/models/discourse_controller_reads.rb", discourse_methods.join("\n"))
append_to_owner.call("app/controllers/application_controller.rb", method.call("app/controllers/application_controller.rb", :set_layout))
File.write(File.join(build, "original_topic_urls.rb"), "module OriginalTopicUrls\n#{method.call("app/models/topic.rb", :url, false)}\nend\n")
proof = {pin: pin, original_source_sha256: inputs, selected_spans: spans,
  message_bus_cache_package: message_proof,
  framework: framework.transform_values { |item| item.reject { |key, _| key == :bytes } },
  cut_append_node_start_byte_in_compiled_method: node.location.start_offset,
  source_prefix_sha256: Digest::SHA256.hexdigest(native), original_compiled_template_sha256: Digest::SHA256.hexdigest(compiled),
  original_renderer_methods_sha256: Digest::SHA256.hexdigest(renderer_methods.join("\n")),
  layout_path: File.join(root, "discourse/app/views/layouts/application.html.erb"), layout_sha256: Digest::SHA256.hexdigest(layout),
  body_path: File.join(root, "discourse/app/views/list/list.erb"),
  effect_boundary: "Category#url @@url_cache.defer_get_set -> DistributedCache/Scheduler::Defer/MessageBus; capability refuses before subscription/enqueue/publication",
  pruned_structurally_nil_branches: pruned.map { |n| n.predicate.slice },
  semantics: "Original layout lookup precedes body; body executes before layout.render; source prefix stops at first category URL cache capability, no layout/body reordering",
  full_template_rendered: false, layout_rendered: false, html200_accepted: false, page_accepted: false}
File.write(File.join(build, "template-prefix-proof.json"), JSON.pretty_generate(proof) + "\n")
