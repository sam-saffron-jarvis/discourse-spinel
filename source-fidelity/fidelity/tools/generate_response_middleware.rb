# frozen_string_literal: true
# Source-derived response middleware. No observed response/settings values.
require "prism"
require "digest"
require "json"
require "open3"

def generate_response_middleware(root)
  pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
  sources = {}
  spans = []
  read = lambda do |path|
    source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
    raise "missing pinned middleware #{path}" unless status.success?
    raise "original middleware changed #{path}" unless File.binread(File.join(root, "discourse", path)) == source.b
    sources[path] = Digest::SHA256.hexdigest(source)
    source
  end
  constant = lambda do |path, name|
    source = read.call(path)
    found = nil
    visit = lambda do |node|
      found = node if node.is_a?(Prism::ConstantWriteNode) && node.name == name
      node.compact_child_nodes.each { |child| visit.call(child) }
    end
    visit.call(Prism.parse(source).value)
    raise "middleware declaration missing #{path}:#{name}" unless found
    spans << {source: path, start_byte: found.location.start_offset, end_byte: found.location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(found.slice)}
    found.slice
  end
  declarations = [constant.call("lib/markdown_endpoint/request_constraint.rb", :VARY_ACCEPT_ENV_KEY),
                  constant.call("lib/middleware/request_tracker.rb", :MAX_SESSION_ID_LENGTH)]
  fast_blank_path = "fast_blank-1.0.1/ext/fast_blank/fast_blank.c"
  fast_blank = File.binread(File.join(root, "run/bundle/ruby/4.0.0/gems", fast_blank_path))
  raise "actual fast_blank predicate changed" unless fast_blank.include?("if (!rb_isspace(cc) && cc != 0) return Qfalse;")
  text = <<~RUBY
    # frozen_string_literal: true
    # GENERATED genuine response middleware; all other stack entries unaccepted.
    require "securerandom"
    module PortableResponseMiddlewareDeclarations
      #{declarations.join("\n")}
      # The actual Discourse fast_blank1.0.1 override (rb_isspace or NUL),
      # NOT ActiveSupport's Unicode whitespace blank_as? predicate.
      # Header values outside this Rack profile refuse explicitly.
      def self.blank_header?(value)
        return true if value.nil?
        raise ArgumentError, "unsupported non-string response header profile" unless value.is_a?(String)
        value.match?(/\\A[\\x00\\x09-\\x0d\\x20]*\\z/)
      end
    end
  RUBY
  %w[lib/markdown_endpoint/vary_middleware.rb lib/middleware/track_view_session_id_injector.rb lib/middleware/csp_script_nonce_injector.rb].each do |path|
    source = read.call(path)
    spans << {source: path, start_byte: 0, end_byte: source.bytesize, text_sha256: Digest::SHA256.hexdigest(source)}
    source = source.gsub("RequestConstraint::VARY_ACCEPT_ENV_KEY", "PortableResponseMiddlewareDeclarations::VARY_ACCEPT_ENV_KEY")
    source = source.gsub("Middleware::RequestTracker::MAX_SESSION_ID_LENGTH", "PortableResponseMiddlewareDeclarations::MAX_SESSION_ID_LENGTH")
    source = source.sub("reject(&:blank?)", "reject { |token| PortableResponseMiddlewareDeclarations.blank_header?(token) }")
    source = source.sub('headers[name].blank?', 'PortableResponseMiddlewareDeclarations.blank_header?(headers[name])')
    text += source + "\n"
  end
  raise "invalid response middleware" unless Prism.parse(text).success?
  target = "compat/framework/portable_json_response_middleware.rb"
  File.binwrite(File.join(root, "fidelity", target), text)
  request_id_target = "compat/framework/portable_discourse_request_id_middleware.rb"
  request_id_text = <<~RUBY
    # frozen_string_literal: true
    # Actual Actionpack RequestId presence/sanitization algorithm in the
    # Discourse fast_blank context; same env/call boundary as the framework.
    class PortableDiscourseRequestIdMiddleware < ActionDispatch::RequestIdMiddleware
      def make_request_id(request_id)
        if PortableResponseMiddlewareDeclarations.blank_header?(request_id)
          SecureRandom.uuid
        else
          request_id.gsub(/[^\\w\\-@]/, "")[0, 255]
        end
      end
    end
  RUBY
  File.binwrite(File.join(root, "fidelity", request_id_target), request_id_text)
  cors_path = "config/initializers/008-rack-cors.rb"
  cors_source = read.call(cors_path)
  cors_class = Prism.parse(cors_source).value.statements.body.grep(Prism::ClassNode).first
  raise "actual CORS middleware class changed" unless cors_class && cors_class.constant_path.slice == "Discourse::Cors"
  spans << {source: cors_path, start_byte: cors_class.location.start_offset, end_byte: cors_class.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(cors_class.slice)}
  cors = cors_class.slice
  cors = cors.gsub("GlobalSetting.enable_cors", "SiteSetting.portable_cors_enabled?")
  cors = cors.gsub("GlobalSetting.cors_origin.present?", "!PortableResponseMiddlewareDeclarations.blank_header?(SiteSetting.portable_cors_origin)")
  cors = cors.gsub("GlobalSetting.cors_origin.split", "SiteSetting.portable_cors_origin.to_s.split")
  cors = cors.gsub("GlobalSetting.cdn_url", "SiteSetting.portable_rendering_asset_host")
  cors = cors.gsub("SiteSetting.cors_origins.present?", "!PortableResponseMiddlewareDeclarations.blank_header?(PortableCorsReadContext.site_origins)")
  cors = cors.gsub("SiteSetting.cors_origins.split", "PortableCorsReadContext.site_origins.split")
  cors = cors.sub("cors_origins = cors_origins.presence", "cors_origins = cors_origins.empty? ? nil : cors_origins")
  cors = cors.sub("cors_origins.exclude?(origin)", "!cors_origins.include?(origin)")
  cors_text = <<~RUBY
    # frozen_string_literal: true
    # GENERATED original CORS algorithm; configuration/store stay live.
    module PortableCorsReadContext
      def self.site_origins
        value = SiteSetting.cors_origins
        raise ArgumentError, "unsupported non-string site CORS origins" unless value.is_a?(String)
        value
      end
    end
    #{cors}
  RUBY
  raise "invalid source CORS component" unless Prism.parse(cors_text).success?
  cors_target = "compat/framework/portable_cors_middleware.rb"
  File.binwrite(File.join(root, "fidelity", cors_target), cors_text)
  {baseline_revision: pin, source_sha256: sources, selected_spans: spans,
   cors_candidate: cors_target, cors_candidate_sha256: Digest::SHA256.hexdigest(cors_text),
   framework_source_sha256: {fast_blank_path => Digest::SHA256.hexdigest(fast_blank)},
   request_id_candidate: request_id_target, request_id_candidate_sha256: Digest::SHA256.hexdigest(request_id_text),
   candidate: target, candidate_sha256: Digest::SHA256.hexdigest(text),
   implemented_classes: ["MarkdownEndpoint::VaryMiddleware", "Discourse::Cors", "Middleware::TrackViewSessionIdInjector", "Middleware::CspScriptNonceInjector"],
   transformations: ["Two original constant declarations have explicit source-owned namespace bindings; no configuration values",
     "Discourse's actual fast_blank1.0.1 String/nil predicate (rb_isspace or NUL) replaces Ruby blank? dispatch; non-String headers refuse",
     "RequestId method retains original presence-before-sanitization in actual fast_blank context; Ruby first(255) becomes standard String[0,255]",
     "CORS uses real shared global configuration and SiteSetting store, source blank semantics, Array empty?/include? equivalents; no forced settings or captured origins"],
   full_stack_accepted: false, observed_payloads_as_inputs: false}
end
