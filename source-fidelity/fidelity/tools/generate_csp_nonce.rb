# frozen_string_literal: true
require "prism"
require "json"
require "digest"
require "open3"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
sources = {}
spans = []
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "original CSP source changed" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  sources[path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |path, &predicate|
  found = []
  visit = lambda do |node|
    found << node if predicate.call(node)
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(read.call(path)).value)
  raise "CSP source boundary changed #{path}" unless found.length == 1
  node = found.first
  spans << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
            text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
nonce = select.call("lib/content_security_policy.rb") { |n| n.is_a?(Prism::DefNode) && n.name == :nonce_placeholder }
nonce = nonce.sub("def nonce_placeholder(", "def self.nonce_placeholder(")
cacheable = select.call("lib/middleware/anonymous_cache.rb") { |n| n.is_a?(Prism::ConstantWriteNode) && n.name == :CACHEABLE_ENV }
helper = select.call("app/helpers/application_helper.rb") { |n| n.is_a?(Prism::DefNode) && n.name == :csp_nonce_placeholder }
injector = read.call("lib/middleware/csp_script_nonce_injector.rb")
# Reuse the already source-backed fast_blank header profile, not another copy
# of the predicate and not ActiveSupport's differing Unicode-only semantics.
response_path = File.join(root, "fidelity/compat/framework/portable_json_response_middleware.rb")
response_source = File.read(response_path)
declaration = Prism.parse(response_source).value.statements.body.grep(Prism::ModuleNode).find do |n|
  n.constant_path.slice == "PortableResponseMiddlewareDeclarations"
end
raise "header declaration missing" unless declaration
header = "# frozen_string_literal: true\n# GENERATED isolated CSP nonce dependency, not policy construction or a request.\nrequire \"securerandom\"\n"
common = "module Middleware; class AnonymousCache; #{cacheable}; end; end\nclass ContentSecurityPolicy\n#{nonce}\nend\nmodule UnitCspNonceMethod\n#{helper}\nend\n"
original = header + common + injector
candidate = header + declaration.slice + "\n" + common + injector.sub('headers[name].blank?', 'PortableResponseMiddlewareDeclarations.blank_header?(headers[name])')
raise "invalid CSP candidate" unless Prism.parse(candidate).success?
File.write(File.join(root, "fidelity/compat/discourse/lib/portable_csp_nonce.rb"), candidate)
File.write(ARGV.fetch(0), original)
proof = {pin: pin, original_source_sha256: sources, selected_spans: spans,
  original_injector_whole_file_sha256: Digest::SHA256.hexdigest(injector), candidate_sha256: Digest::SHA256.hexdigest(candidate),
  header_adapter_sha256: Digest::SHA256.hexdigest(declaration.slice),
  transformations: ["Singleton-class nonce_placeholder emitted as explicit self method",
    "Exact anonymous cache key declaration only, NOT cache implementation",
    "Existing actual fast_blank response-header adapter; complete original nonce injector retained"],
  context: "Unit request env/response headers/policy strings only; genuine SecureRandom, no captured production nonce",
  original_html_accepted: false, native_html_accepted: false, browser_accepted: false, page_accepted: false}
File.write(File.join(root, "fidelity/compat/discourse/portable_csp_nonce.json"), JSON.pretty_generate(proof) + "\n")
puts "Generated source-backed CSP nonce provider/injector dependency"
