# frozen_string_literal: true
require "prism"
require "digest"
require "json"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
path = "app/views/layouts/application.html.erb"
source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
raise "original preload layout changed" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
start = source.index("      <discourse-assets-json>\n")
finish = source.index("      </discourse-assets-json>\n", start)
raise "preload source span missing" unless start && finish
finish += "      </discourse-assets-json>\n".length
fragment = source[start...finish]
raise "preload expression changed" unless fragment.scan(/<%=(.*?)%>/m) == [[" raw(preloaded_json) "]]
File.write(ARGV.fetch(0), fragment)
compiled = ActionView::Template::Handlers::ERB::Erubi.new(fragment, escape: false, trim: true).src
original = "module PortableApplicationPreloadFragment\ndef render_preload_fragment\n@output_buffer = ActionView::OutputBuffer.new\n#{compiled}\n@output_buffer.to_s\nend\nend\n"
File.write(ARGV.fetch(1), original)
left, right = fragment.split("<%= raw(preloaded_json) %>", 2)
candidate = <<~RUBY
  # frozen_string_literal: true
  # GENERATED exact original preload script span; not real Site/preload data.
  module PortableApplicationPreloadFragment
    def render_preload_fragment
      output = +#{left.dump}
      value = preloaded_json
      raise TypeError, "preloaded JSON must be a String" unless value.is_a?(String)
      # Original raw(value) => value.to_s.html_safe; do not HTML-escape JSON.
      output << value
      output << #{right.dump}
      ActionView::HtmlFragment.new(output)
    end
  end
RUBY
raise "invalid preload fragment" unless Prism.parse(candidate).success?
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_application_preload_fragment.rb"), candidate)
helper = File.join(root, "run/bundle/ruby/4.0.0/gems/actionview-8.1.4/lib/action_view/helpers/output_safety_helper.rb")
raw_node = nil
visit = lambda do |node|
  raw_node = node if node.is_a?(Prism::DefNode) && node.name == :raw
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse_file(helper).value)
raise "original raw helper missing" unless raw_node
proof = {pin: pin, source: path, source_sha256: Digest::SHA256.hexdigest(source),
  selected_span: {start_byte: start, end_byte: finish, text_sha256: Digest::SHA256.hexdigest(fragment)},
  raw_helper: {source: "actionview-8.1.4/lib/action_view/helpers/output_safety_helper.rb", start_byte: raw_node.location.start_offset,
    end_byte: raw_node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(raw_node.slice)},
  candidate_sha256: Digest::SHA256.hexdigest(candidate), original_compiled_sha256: Digest::SHA256.hexdigest(original),
  transformations: ["Original HTML Erubi/OutputBuffer reference; exact literal span retained",
    "raw(preloaded_json) String-to-trusted boundary inlined; helper acquisition/escape logic unchanged"],
  context: "Unit preloader strings/nil in actual minimal ActionView JSON context (standalone JSON gem), NOT Site/settings data or full Rails/Oj encoding",
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_application_preload_fragment.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated concrete original data-preloaded ERB fragment"
