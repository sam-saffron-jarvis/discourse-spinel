# frozen_string_literal: true
require "prism"
require "digest"
require "json"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
root = File.expand_path("../..", __dir__)
app, build = ARGV
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, source: {}, spans: [], html_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "compiler prefix source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  proof[:source][path] = Digest::SHA256.hexdigest(text)
  text
end
method = lambda do |source, name|
  nodes = []
  walk = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(Prism.parse(source).value)
  raise "compiler prefix source ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
theme = read.call("app/models/theme.rb")
processor = read.call("lib/asset_processor.rb")
base = processor[/BASE_COMPILER_VERSION = ([0-9]+)/, 1]
raise "asset compiler version declaration changed" unless base
compiler_version = method.call(theme, :compiler_version)
native_compiler_version = compiler_version.sub('get_set_cache "compiler_version" do', 'cache = CategoryCacheBootstrap.theme_compiler_cache; raise "unbound concrete compiler cache" unless cache.is_a?(CategoryCacheApplication::DistributedCache); cache.defer_get_set("compiler_version") do')
raise "compiler cache source anchor changed" if native_compiler_version == compiler_version
raw_js_assets = method.call(theme, :js_asset_info).gsub("Theme.compiler_version", "ListThemeCompilerSource.compiler_version")
js_assets = raw_js_assets.sub("theme_id.blank?", "ActiveSupport.blank?(theme_id)")
node = Prism.parse(js_assets).value.statements.body.first
call = node.body.body.last
raise "source Theme cache block changed" unless call.is_a?(Prism::CallNode) && call.name == :get_set_cache && call.block
js_assets[call.block.body.location.start_offset, call.block.body.location.length] = 'raise "unacquired array/bake callback entered"'
File.write(File.join(build, "original_theme_js_prefix.rb"), "module ListThemeCompilerSource\n#{compiler_version}\n#{raw_js_assets}\nend\n")
File.write(File.join(build, "list_compiler_source.rb"), "module ListCompilerSource\nBASE_COMPILER_VERSION = #{base}\nTHEME_CACHE_KEY = #{("theme:compiler:" + base).inspect}\nend\nmodule ListThemeCompilerSource\ndef self.transform_ids(id); ::Theme.transform_ids(id); end\n#{native_compiler_version}\n#{js_assets}\nend\n")
partial = read.call("app/views/layouts/_plugin_js.html.erb")
anchor = '<%= generate_import_map(plugin_assets) %>'
finish = partial.index(anchor)
raise "importmap partial boundary changed" unless finish
prefix = partial[0, finish + anchor.length] + "\n<% end %>"
compiled = ActionView::Template::Handlers::ERB::Erubi.new(prefix, escape: false, trim: true).src
File.write(File.join(build, "native_importmap_prefix.rb"), "module NativeImportMapPrefix\ndef render_plugin_js_prefix(opts)\n#{compiled}\nend\nend\n")
full = ActionView::Template::Handlers::ERB::Erubi.new(partial, escape: false, trim: true).src
File.write(File.join(build, "original_importmap_prefix.rb"), "module OriginalImportMapPrefix\ndef render_plugin_js_prefix(opts)\n#{full}\nend\nend\n")
discourse = read.call("lib/discourse.rb")
registry = method.call(discourse, :plugins)
filters = method.call(discourse, :asset_filter_options).gsub('request.blank?', 'ActiveSupport.blank?(request)').gsub('path.present?', 'ActiveSupport.present?(path)')
File.write(File.join(build, "native_importmap_registry.rb"), "module Discourse\n#{registry}\n#{filters}\ndef self.find_plugin_js_assets(opts)\nraise ArgumentError, 'unsupported loaded importmap plugins' unless plugins.empty?\nasset_filter_options(:js, opts[:request])\n[]\nend\nend\n")
raw = [:plugins, :find_plugins, :apply_asset_filters, :asset_filter_options, :find_plugin_js_assets].map { |name| method.call(discourse, name) }
File.write(File.join(build, "original_importmap_registry.rb"), "module Discourse\n#{raw.join("\n")}\nend\n")
nonce = method.call(read.call("lib/content_security_policy.rb"), :nonce_placeholder).sub('def nonce_placeholder(', 'def self.nonce_placeholder(')
File.write(File.join(build, "importmap_nonce_source.rb"), "module Middleware; class AnonymousCache; CACHEABLE_ENV = \"discourse.anonymous_cache.cacheable\"; end; end\nclass ContentSecurityPolicy\n#{nonce}\nend\n")
helper = read.call("app/helpers/application_helper.rb")
File.write(File.join(build, "original_compiler_helpers.rb"), "module OriginalCompilerHelpers\n#{method.call(helper, :generate_import_map)}\n#{method.call(helper, :theme_js_assets)}\n#{method.call(helper, :csp_nonce_placeholder)}\nend\n")
proof[:transformations] = ["native no-loaded-plugin profile checked against original registry before source-proven loop folding", "original full plugin_js ERB reference; native prefix stops inside real generate_import_map", "source Theme compiler dependency prefix; no array cache/bake skip or fabricated assets"]
File.write(File.join(build, "importmap-compiler-source-proof.json"), JSON.pretty_generate(proof) + "\n")
