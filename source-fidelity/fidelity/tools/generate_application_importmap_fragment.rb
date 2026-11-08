# frozen_string_literal: true
require "prism"
require "json"
require "digest"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
sources = {}
spans = []
read = lambda do |path|
  bytes, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "original import-map source changed #{path}" unless status.success? && bytes.b == File.binread(File.join(root, "discourse", path))
  sources[path] = Digest::SHA256.hexdigest(bytes)
  bytes
end
app = read.call("app/helpers/application_helper.rb")
owner = Prism.parse(app).value.statements.body.grep(Prism::ModuleNode).first
method = owner.body.body.grep(Prism::DefNode).find { |n| n.name == :generate_import_map }
raise "import-map helper missing" unless method
spans << {source: "app/helpers/application_helper.rb", start_byte: method.location.start_offset, end_byte: method.location.end_offset,
          text_sha256: Digest::SHA256.hexdigest(method.slice)}
plugin_source = read.call("lib/plugin/js_manager.rb")
stubs = []
visit = lambda do |node|
  if node.is_a?(Prism::DefNode) && %i[optional_plugin_stub required_plugin_stub].include?(node.name)
    stubs << node.slice
    spans << {source: "lib/plugin/js_manager.rb", start_byte: node.location.start_offset, end_byte: node.location.end_offset,
              text_sha256: Digest::SHA256.hexdigest(node.slice)}
  end
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(plugin_source).value)
raise "plugin stub boundary changed" unless stubs.length == 2
partial_path = "app/views/layouts/_plugin_js.html.erb"
partial = read.call(partial_path)
start = partial.index('  <script type="importmap"')
finish = partial.index("  </script>\n", start) + "  </script>\n".length
fragment = partial[start...finish]
spans << {source: partial_path, start_byte: start, end_byte: finish, text_sha256: Digest::SHA256.hexdigest(fragment)}
File.write(ARGV.fetch(0), fragment)
engine = ActionView::Template::Handlers::ERB::Erubi.new(fragment, escape: false, trim: true).src
original = "module Plugin; class JsManager\n#{stubs.join("\n")}\nend; end\nmodule PortableImportMapMethods\n#{method.slice}\ndef render_importmap_fragment(plugin_assets)\n@output_buffer = ActionView::OutputBuffer.new\n#{engine}\n@output_buffer.to_s\nend\nend\n"
File.write(ARGV.fetch(1), original)
helper = method.slice.sub("EmberAssets.import_map", "asset_import_map")
helper = helper.sub("JSON.pretty_generate({ imports: }).html_safe", "ActionView::HtmlFragment.new(JSON.pretty_generate({ imports: }))")
# Preserve the exact concrete two-expression span and typed safe boundaries.
left, rest = fragment.split("<%= csp_nonce_placeholder %>", 2)
middle, right = rest.split("<%= generate_import_map(plugin_assets) %>", 2)
raise "unsupported import-map ERB expressions" unless left && middle && right
candidate = <<~RUBY
  # frozen_string_literal: true
  # GENERATED import-map helper + concrete source span, NOT plugin activation.
  module Plugin; class JsManager
  #{stubs.join("\n")}
  end; end
  module PortableImportMapMethods
  #{helper}
    def render_importmap_fragment(plugin_assets)
      output = +#{left.dump}
      nonce = csp_nonce_placeholder
      raise TypeError, "non-string import-map nonce" unless nonce.is_a?(String)
      output << ERB::Util.html_escape(nonce)
      output << #{middle.dump}
      imports = generate_import_map(plugin_assets)
      raise TypeError, "untrusted import-map JSON" unless imports.is_a?(ActionView::HtmlFragment)
      output << imports.to_s
      output << #{right.dump}
      ActionView::HtmlFragment.new(output)
    end
  end
RUBY
raise "invalid import-map lowering" unless Prism.parse(candidate).success?
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_application_importmap_fragment.rb"), candidate)
proof = {pin: pin, source_sha256: sources, selected_spans: spans, candidate_sha256: Digest::SHA256.hexdigest(candidate),
  original_compiled_sha256: Digest::SHA256.hexdigest(original),
  transformations: ["Explicit live genuine asset_import_map replaces EmberAssets global in native helper",
    "Exact original plugin stub methods retained; unit plugin/theme vectors are supplied, not activation",
    "Actual ActionView HTML ERB reference; String nonce escapes and typed trusted JSON appends raw",
    "Only the concrete import-map script span is rendered, not outer Discourse.find_plugin_js_assets or complete partial"],
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_application_importmap_fragment.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated actual import-map helper and concrete original ERB span"
