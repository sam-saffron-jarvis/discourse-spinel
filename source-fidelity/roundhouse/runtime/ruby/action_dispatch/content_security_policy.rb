# frozen_string_literal: true

# ActionDispatch::ContentSecurityPolicy — the header Rails' middleware
# writes after the controller returns.
#
# Campfire's `InlineScriptHashes` narrows `script-src` on the request's
# policy during a before_action, including when an around_action serves
# a cached page and never yields. The header is applied after that
# around filter returns, which is where Rails' middleware runs. A
# request with no policy (the framework default, or
# DISABLE_CONTENT_SECURITY_POLICY) writes nothing.
module ActionDispatch
  class ContentSecurityPolicy
    class InvalidDirectiveError < StandardError; end

    # Rails 8.1.4 source mappings. The DSL bridge below is separate from
    # set_directive, whose callers already supply quoted source strings.
    SOURCE_MAPPINGS = {
      self: "'self'", unsafe_eval: "'unsafe-eval'", wasm_unsafe_eval: "'wasm-unsafe-eval'",
      unsafe_hashes: "'unsafe-hashes'", unsafe_inline: "'unsafe-inline'", none: "'none'",
      http: "http:", https: "https:", data: "data:", mediastream: "mediastream:",
      allow_duplicates: "'allow-duplicates'", blob: "blob:", filesystem: "filesystem:",
      report_sample: "'report-sample'", script: "'script'", strict_dynamic: "'strict-dynamic'",
      ws: "ws:", wss: "wss:"
    }.freeze
    SOURCE_DIRECTIVES = %w[base-uri child-src connect-src default-src font-src form-action
      frame-ancestors frame-src img-src manifest-src media-src object-src prefetch-src
      require-trusted-types-for script-src script-src-attr script-src-elem style-src
      style-src-attr style-src-elem trusted-types worker-src report-uri].freeze

    def initialize
      @names = []
      @values = []
      @bare_names = []
    end

    # The concern reads and replaces `policy.directives["script-src"]`.
    # Returning self keeps `[]` / `[]=` on this object; the stored value
    # is the source list, which is what `sources - ["'self'"]` expects.
    def directives
      self
    end

    def [](name)
      i = find_name(name.to_s)
      return nil if i < 0
      @values[i]
    end

    def []=(name, value)
      key = name.to_s
      @bare_names.delete(key)
      i = find_name(key)
      if i < 0
        @names << key
        @values << value
      else
        @values[i] = value
      end
      nil
    end

    # Synthesized boot code calls this with the sources already quoted
    # (`"'self'"`, `"'none'"`). One directive, replaced wholesale, which
    # is what `policy.script_src :self` does.
    def set_directive(name, sources)
      self.[]=(name, sources)
      nil
    end

    # Typed bridge for the actual Rails directive DSL (no dynamic procs).
    # Empty source-list directives DELETE, while the upgrade flag is bare.
    def set_source_directive(name, sources)
      if name == "upgrade-insecure-requests"
        raise ArgumentError, "unsupported upgrade directive sources" unless sources.empty?
        set_flag_directive(name, true)
      else
        raise ArgumentError, "unsupported content security policy directive: #{name}" unless SOURCE_DIRECTIVES.include?(name)
        if name == "report-uri"
          raise ArgumentError, "report-uri requires exactly one source" unless sources.length == 1
          # Rails report_uri bypasses apply_mappings; resolve_source converts
          # Symbols to their names and does NOT quote hash-looking URI strings.
          source = sources.first
          raise ArgumentError, "unsupported report-uri source type" unless source.is_a?(String) || source.is_a?(Symbol)
          self.[]=(name, [source.to_s])
        elsif sources.empty?
          remove_directive(name)
        else
          mapped = sources.map { |source| map_source(source) }
          self.[]=(name, mapped)
        end
      end
      nil
    end

    def set_flag_directive(name, enabled)
      raise ArgumentError, "unsupported CSP flag directive" unless name == "upgrade-insecure-requests" || name == "block-all-mixed-content" || name == "sandbox"
      if enabled
        self.[]=(name, [])
        @bare_names << name
      else
        remove_directive(name)
      end
      nil
    end

    def flag_directive?(name)
      @bare_names.include?(name)
    end

    def remove_directive(name)
      index = find_name(name)
      if index >= 0
        @names.delete_at(index)
        @values.delete_at(index)
      end
      @bare_names.delete(name)
      nil
    end

    def map_source(source)
      if source.is_a?(Symbol)
        mapped = SOURCE_MAPPINGS[source]
        raise ArgumentError, "Unknown content security policy source mapping: #{source.inspect}" unless mapped
        mapped
      elsif source.is_a?(String)
        if source.start_with?("sha256-") || source.start_with?("sha384-") || source.start_with?("sha512-")
          "'#{source}'"
        else
          source
        end
      else
        raise ArgumentError, "Invalid content security policy source: #{source.inspect}"
      end
    end

    def validate_source(name, source)
      if source.include?(";") || source != source.gsub(/[[:space:]]/, "")
        message = "Invalid Content Security Policy #{name}: \"#{source}\". " +
          "Directive values must not contain whitespace or semicolons. " +
          "Please use multiple arguments or other directive methods instead."
        raise InvalidDirectiveError, message.gsub(/[[:space:]]+/, " ").strip
      end
      nil
    end

    def validate_sources(name, sources)
      index = 0
      while index < sources.length
        validate_source(name, sources[index])
        index += 1
      end
      nil
    end

    def worker_src(source)
      self.[]=("worker-src", [source])
      nil
    end

    def build
      n = @names.length
      return "" if n == 0
      i = 0
      out = +""
      while i < n
        out = out + "; " if i > 0
        out = out + @names[i].to_s
        unless @bare_names.include?(@names[i])
          validate_sources(@names[i], @values[i])
          out = out + " " + join_sources(@values[i])
        end
        i += 1
      end
      out
    end

    def dup
      copy = ContentSecurityPolicy.new
      i = 0
      n = @names.length
      while i < n
        if @bare_names.include?(@names[i])
          copy.set_flag_directive(@names[i], true)
        else
          copy.set_directive(@names[i].to_s, copy_sources(@values[i]))
        end
        i += 1
      end
      copy
    end

    def self.write_header(controller)
      req = controller.request
      return nil if req.nil?
      policy = req.content_security_policy
      return nil if policy.nil?
      built = policy.build
      return nil if built.empty?
      controller.headers["Content-Security-Policy"] = built
      nil
    end

    def find_name(name)
      i = 0
      n = @names.length
      while i < n
        return i if @names[i] == name
        i += 1
      end
      -1
    end

    def copy_sources(list)
      return [] if list.nil?
      out = []
      i = 0
      n = list.length
      while i < n
        item = list[i]
        out << item.to_s unless item.nil?
        i += 1
      end
      out
    end

    def join_sources(list)
      return "" if list.nil?
      n = list.length
      return "" if n == 0
      i = 0
      out = +""
      while i < n
        out = out + " " if i > 0
        item = list[i]
        out = out + item.to_s unless item.nil?
        i += 1
      end
      out
    end
  end
end
