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
raise "original layout changed" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
start = source.index('    <link rel="preload" href="<%= script_asset_path "js/browser-update" %>"')
last = source.index('    <%- unless customization_disabled? %>', start + 1)
raise "concrete asset fragment changed" unless start && last
fragment = source[start...last]
raise "wrong concrete asset fragment" unless fragment.include?('module_preloads_for "discourse", (staff? ? "admin/compat-modules" : nil)')
File.write(ARGV.fetch(0), fragment)
# This is the ACTUAL ActionView HTML ERB mode (HTML isn't escape_ignore_list).
# escape:false means OutputBuffer.append=, whose safe?/escape behavior is real.
original_code = ActionView::Template::Handlers::ERB::Erubi.new(fragment, escape: false, trim: true).src
original = "module PortableApplicationAssetFragment\ndef render_asset_fragment\n@output_buffer = ActionView::OutputBuffer.new\n#{original_code}\n@output_buffer.to_s\nend\nend\n"
File.write(ARGV.fetch(1), original)
position = 0
parts = []
expressions = []
fragment.to_enum(:scan, /<%=(.*?)%>/m).each do
  match = Regexp.last_match
  literal = fragment[position...match.begin(0)]
  raise "unhandled ERB control code" if literal.include?("<%")
  parts << "output << #{literal.dump}" unless literal.empty?
  expression = match[1].strip
  ast = Prism.parse(expression).value.statements.body
  raise "non-single ERB expression" unless ast.length == 1 && ast.first.is_a?(Prism::CallNode)
  name = ast.first.name
  index = expressions.length
  value = "value_#{index}"
  parts << "#{value} = (#{expression})"
  if %i[preload_script module_preloads_for].include?(name)
    parts << "raise TypeError, \"lost typed trusted fragment\" unless #{value}.is_a?(ActionView::HtmlFragment)"
    parts << "output << #{value}.to_s"
    kind = "trusted_fragment"
  elsif %i[script_asset_path csp_nonce_placeholder].include?(name)
    parts << "raise TypeError, \"non-string layout expression\" unless #{value}.is_a?(String)"
    parts << "output << ERB::Util.html_escape(#{value})"
    kind = "escaped_string"
  else
    raise "unsupported concrete layout expression #{name}"
  end
  expressions << {ruby: expression, return_boundary: kind, start_byte: start + match.begin(0), end_byte: start + match.end(0)}
  position = match.end(0)
end
parts << "output << #{fragment[position..].dump}"
raise "unexpected expression count" unless expressions.length == 4
candidate = "# frozen_string_literal: true\n# GENERATED concrete pinned application layout asset fragment, NOT a page.\nrequire \"erb\"\nmodule PortableApplicationAssetFragment\ndef render_asset_fragment\noutput = +\"\"\n#{parts.join("\n")}\nActionView::HtmlFragment.new(output)\nend\nend\n"
raise "invalid typed fragment" unless Prism.parse(candidate).success?
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_application_asset_fragment.rb"), candidate)
proof = {pin: pin, source: path, source_sha256: Digest::SHA256.hexdigest(source),
  selected_span: {start_byte: start, end_byte: last, text_sha256: Digest::SHA256.hexdigest(fragment)},
  expressions: expressions, candidate_sha256: Digest::SHA256.hexdigest(candidate),
  original_erb_engine: "ActionView::Template::Handlers::ERB::Erubi escape:false/trim:true, actual OutputBuffer.append= semantics",
  original_compiled_sha256: Digest::SHA256.hexdigest(original),
  transformations: ["Exact original literal bytes retained; each Ruby expression executes once",
    "Source-backed String expressions escape; existing typed trusted fragments append raw; explicit result wrapper",
    "No other layout branch removed or represented as rendered; this is only the selected source span"],
  context: "Unit settings/roles and isolated CSP headers/env, real file resolver/genuine graph; NOT a request/page or production configuration",
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_application_asset_fragment.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated concrete original layout asset fragment and actual ERB reference"
