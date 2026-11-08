# frozen_string_literal: true
require "prism"
require "digest"
require "fileutils"
require "open3"

# Source-derived supported call paths, not full optional subsystems. Every
# excluded path raises, and the manifest retains full references and spans.
def generate_json_profile_middleware(root, framework_read, parts)
  sources = {}
  spans = []
  read_app = lambda do |path|
    original, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8:#{path}")
    raise "original profile source changed #{path}" unless status.success? && File.binread(File.join(root, "discourse", path)) == original.b
    target = File.join(root, "fidelity/source/discourse", path)
    raise "immutable profile reference changed" if File.exist?(target) && File.binread(target) != original.b
    FileUtils.mkdir_p(File.dirname(target))
    File.binwrite(target, original) unless File.exist?(target)
    sources[path] = Digest::SHA256.hexdigest(original)
    original
  end
  methods = lambda do |source, path|
    found = {}
    visit = lambda do |node|
      if node.is_a?(Prism::DefNode)
        found[node.name] ||= node
      else
        node.compact_child_nodes.each { |child| visit.call(child) }
      end
    end
    visit.call(Prism.parse(source).value)
    found.each_value do |node|
      next unless %i[initialize call html_response? allowed_methods].include?(node.name)
      spans << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
        text_sha256: Digest::SHA256.hexdigest(node.slice)}
    end
    found
  end
  text = +"# frozen_string_literal: true\n# GENERATED supported JSON call-path projections. Optional paths REFUSE.\n"
  classes = []
  add = lambda do |name, init, body, extras = ""|
    text << "class #{name}\n#{init}\ndef call(env)\n#{body}\nend\n#{extras}\nend\n"
    classes << name
  end
  path = "lib/middleware/omniauth_bypass_middleware.rb"
  m = methods.call(read_app.call(path), path)
  guard = m.fetch(:call).body.body.first
  raise "actual auth bypass guard changed" unless guard.is_a?(Prism::UnlessNode) && guard.slice.include?('start_with?("/auth")')
  # Declare the real namespace; the optional OmniAuth Builder is not needed
  # by this source-proven return. Never claim an /auth request works.
  text << "module Middleware\nend\n"
  add.call("Middleware::OmniauthBypassMiddleware", m.fetch(:initialize).slice,
    guard.slice + "\nraise ArgumentError, \"unsupported JSON profile authentication route\"")

  path = "lib/middleware/missing_avatars.rb"
  m = methods.call(read_app.call(path), path)
  statements = m.fetch(:call).body.body
  raise "actual avatar guard changed" unless statements.first.is_a?(Prism::IfNode)
  body = "if #{statements.first.predicate.slice}\nraise ArgumentError, \"unsupported JSON profile missing-avatar route\"\nend\n" + statements.drop(1).map(&:slice).join("\n")
  add.call("Middleware::MissingAvatars", m.fetch(:initialize).slice, body)

  path = "lib/content_security_policy/middleware.rb"
  m = methods.call(read_app.call(path), path)
  statements = m.fetch(:call).body.body
  raise "actual CSP return boundary changed" unless statements[3].is_a?(Prism::UnlessNode) && statements[3].slice == "return response unless html_response?(headers)"
  body = statements.take(4).map(&:slice).join("\n") + "\nraise ArgumentError, \"unsupported JSON profile HTML CSP\""
  body = body.sub("Rack::Request.new(env)", "Rack::CoreRequest.new(env)").sub('headers["Content-Security-Policy"].present?', '!PortableResponseMiddlewareDeclarations.blank_header?(headers["Content-Security-Policy"])')
  text << "class ContentSecurityPolicy\nend\n"
  add.call("ContentSecurityPolicy::Middleware", m.fetch(:initialize).slice, body, m.fetch(:html_response?).slice)

  path = "lib/middleware/crawler_hooks.rb"
  m = methods.call(read_app.call(path), path)
  statements = m.fetch(:call).body.body
  condition = statements[2].predicate
  flatten = lambda { |node| node.is_a?(Prism::AndNode) ? flatten.call(node.left) + flatten.call(node.right) : [node] }
  predicates = flatten.call(condition)
  raise "actual crawler JSON short circuit changed" unless predicates.length == 5 && predicates[2].slice.include?('include?("text/html")')
  body = statements.take(2).map(&:slice).join("\n") + "\nif #{predicates.take(3).map(&:slice).join(' && ')}\nraise ArgumentError, \"unsupported JSON profile crawler HTML\"\nend\n" + statements.last.slice
  body = body.sub("Rack::Request.new(env)", "Rack::CoreRequest.new(env)")
  add.call("Middleware::CrawlerHooks", m.fetch(:initialize).slice, body)

  path = "rack-2.2.24/lib/rack/head.rb"
  m = methods.call(framework_read.call(path), path)
  body = m.fetch(:call).body.body
  condition = body[1].predicate.slice.gsub("REQUEST_METHOD", '"REQUEST_METHOD"').gsub("HEAD", '"HEAD"')
  projected = body.first.slice + "\nif #{condition}\nraise ArgumentError, \"unsupported JSON profile HEAD body\"\nelse\n#{body[1].subsequent.statements.slice}\nend"
  add.call("Rack::Head", m.fetch(:initialize).slice, projected)

  path = "rack-2.2.24/lib/rack/method_override.rb"
  original = framework_read.call(path)
  m = methods.call(original, path)
  body = m.fetch(:call).body.body
  condition = body.first.predicate.slice.gsub("REQUEST_METHOD", '"REQUEST_METHOD"')
  allowed = Prism.parse(original).value.statements.body.first.body.body.first.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :ALLOWED_METHODS }
  raise "actual override methods changed" unless allowed
  spans << {source: path, start_byte: allowed.location.start_offset, end_byte: allowed.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(allowed.slice)}
  projected = "if #{condition}\nraise ArgumentError, \"unsupported JSON profile method override\"\nend\n" + body.last.slice
  add.call("Rack::MethodOverride", m.fetch(:initialize).slice, projected, allowed.slice + "\n" + m.fetch(:allowed_methods).slice)

  # Real configuration declaration selected by the application's load_defaults
  # 8.1 chain, NOT an observed effective-header snapshot. The oracle checks the
  # live Rails configuration against this shared source-derived declaration.
  config_path = "railties-8.1.4/lib/rails/application/configuration.rb"
  config = framework_read.call(config_path)
  defaults = []
  visit = lambda do |node|
    if node.is_a?(Prism::CallNode) && node.name == :default_headers= && node.receiver&.slice == "action_dispatch"
      defaults << node.arguments.arguments.first
    end
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(config).value)
  default = defaults.last
  app_config = read_app.call("config/application.rb")
  raise "actual Rails load-defaults header declaration changed" unless default && app_config.include?("config.load_defaults 8.1") && defaults.length == 2
  parts << {source: config_path, start_byte: default.location.start_offset, end_byte: default.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(default.slice)}
  text << "module PortableDefaultHeaderConfiguration\ndef self.default_headers\n#{default.slice}\nend\nend\n"
  path = "lib/middleware/default_headers.rb"
  original = read_app.call(path)
  m = methods.call(original, path)
  constants = Prism.parse(original).value.statements.body.first.body.body.first.body.body.grep(Prism::ConstantWriteNode)
  constants.each { |node| spans << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)} }
  body = m.fetch(:call).body.slice
  body = body.sub("is_html_response = html_response?(headers)", "is_html_response = html_response?(headers)\n      raise ArgumentError, \"unsupported JSON profile HTML default headers\" if is_html_response")
  body = body.sub("Rails.application.config.action_dispatch.default_headers", "PortableDefaultHeaderConfiguration.default_headers")
  # The HTML-only setting getter remains unreachable behind an explicit
  # profile refusal, not an invented/frozen SiteSetting implementation.
  body = body.sub(/      headers\[\n        "Cross-Origin-Opener-Policy"\n      \] =.*?headers\["Cross-Origin-Opener-Policy"\].nil\?\n/m, "")
  raise "HTML-only setting read was not isolated" if body.include?("SiteSetting.")
  text = text.sub("# frozen_string_literal: true\n", "# frozen_string_literal: true\nrequire \"set\"\n")
  add.call("Middleware::DefaultHeaders", m.fetch(:initialize).slice, body,
    constants.map(&:slice).join("\n") + "\n" + m.fetch(:html_response?).slice)

  raise "invalid JSON profile projection" unless Prism.parse(text).success?
  target = "compat/framework/portable_json_profile_middleware.rb"
  File.binwrite(File.join(root, "fidelity", target), text)
  # Framework references share the outer manifest's audited source-span table.
  parts.concat(spans.select { |part| part[:source].start_with?("rack-") })
  {candidate: target, candidate_sha256: Digest::SHA256.hexdigest(text), application_source_sha256: sources,
   selected_spans: spans, supported_call_classes: classes,
   transformations: ["Only source-proven early-return/short-circuit JSON paths projected; excluded route/method/HTML paths explicitly refuse",
     "Rack env Request construction rebound to the same env-backed CoreRequest adapter",
     "CSP presence uses actual Discourse fast_blank context, not a captured policy or a fake settings getter",
     "Rack constant references expanded to their real header/method strings; HEAD BodyProxy and POST override paths refuse",
     "DefaultHeaders uses actual Rails load_defaults8.1 source declaration, verified against live original configuration; no captured header map",
     "HTML default-header/COOP setting path explicitly refuses; JSON merging and controller precedence retained"],
   full_optional_features_accepted: false, whole_stack_accepted: false, observed_payloads_as_inputs: false}
end
