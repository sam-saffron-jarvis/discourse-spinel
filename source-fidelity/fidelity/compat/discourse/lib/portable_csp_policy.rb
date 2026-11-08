# frozen_string_literal: true
# GENERATED original CSP construction; explicit UNIT data/acquisition context.
class ContentSecurityPolicy
def initialize(context)
@context = context
end
class Default
    attr_reader :directives

    def initialize(context:, report_only: false)
      @context = context
      @directives =
        {}.tap do |directives|
          # `upgrade-insecure-requests` is ignored in a report-only policy, and
          # browsers log a console warning when it is present there, so only
          # emit it for the enforced policy.
          directives[:upgrade_insecure_requests] = [] if @context.settings.force_https && !report_only
          directives[:base_uri] = [:self]
          directives[:object_src] = [:none]
          directives[:script_src] = script_src
          directives[:worker_src] = worker_src
          directives[:frame_ancestors] = frame_ancestors if restrict_embed?
          directives[:manifest_src] = ["'self'"]
          directives[:report_uri] = [report_uri] if !PortableCspUnitProfile.blank?(report_uri)
        end
    end

    private

    def script_src
      sources = %w['strict-dynamic' 'wasm-unsafe-eval']
      sources << "'report-sample'" if !PortableCspUnitProfile.blank?(report_uri)
      sources
    end

    def report_uri
      PortableCspUnitProfile.presence(@context.settings.content_security_policy_report_uri)
    end

    def worker_src
      [:self, "blob:", *worker_asset_host]
    end

    def worker_asset_host
      if @context.assets.use_s3? && !PortableCspUnitProfile.blank?(@context.assets.s3_cdn_url)
        s3_cdn = PortableCspUnitProfile.presence(@context.assets.s3_asset_cdn_url) || @context.assets.s3_cdn_url
        ["#{s3_cdn}/assets/"]
      elsif !PortableCspUnitProfile.blank?(@context.assets.cdn_url)
        ["#{@context.assets.cdn_url}#{@context.base_path}/assets/"]
      else
        []
      end
    end

    def frame_ancestors
      ["'self'", *@context.host_store.pluck(:host).map { |host| "https://#{host}" }]
    end

    def restrict_embed?
      @context.settings.content_security_policy_frame_ancestors && !@context.settings.embed_any_origin
    end
  end
class Builder
    EXTENDABLE_DIRECTIVES = %i[
      base_uri
      frame_ancestors
      manifest_src
      object_src
      script_src
      worker_src
    ].freeze

    # Make extending these directives no-op, until core includes them in default CSP
    TO_BE_EXTENDABLE = %i[
      connect_src
      default_src
      font_src
      form_action
      frame_src
      img_src
      media_src
      prefetch_src
      style_src
    ].freeze

    def initialize(context:, base_url:, report_only: false)
      @context = context
      @directives = Default.new(context: context, report_only: report_only).directives
      @base_url = base_url
    end

    def <<(extension)
      PortableCspUnitProfile.validate_extension!(extension)
      return unless valid_extension?(extension)

      extension.each do |directive, sources|
        extend_directive(normalize_directive(directive), sources)
      end
    end

    def build
      policy = ActionDispatch::ContentSecurityPolicy.new

      @directives.each do |directive, sources|
        if sources.is_a?(Array)
          policy.set_source_directive(directive.to_s.gsub("_", "-"), sources)
        else
          raise ArgumentError, "unsupported non-array built directive profile"
        end
      end

      policy.build
    end

    private

    def normalize_directive(directive)
      directive.to_s.gsub("-", "_").to_sym
    end

    def normalize_source(source)
      if source.start_with?("/")
        "#{@base_url}#{source}"
      else
        source
      end
    end

    def extend_directive(directive, sources)
      return unless extendable?(directive)

      @directives[directive] ||= []

      sources = Array(sources).map { |s| normalize_source(s) }

      if %w[script_src worker_src].include?(directive.to_s)
        # Strip any sources which are ignored under strict-dynamic
        # If/when we make strict-dynamic the only option, we could print deprecation warnings
        # asking plugin/theme authors to remove the unnecessary config
        sources =
          sources.reject { |s| s == "'unsafe-inline'" || s == "'self'" || !s.start_with?("'") }
      end

      sources.each do |source|
        # mirrors validation check in ActionDispatch::ContentSecurityPolicy https://github.com/rails/rails/blob/5558e72f22fc69c1c407b31ac5fb3b4ce087b542/actionpack/lib/action_dispatch/http/content_security_policy.rb#L337
        if source.include?(";") || source != source.gsub(/[[:space:]]/, "")
          @context.logger.warn((<<~MSG).gsub(/[[:space:]]+/, " ").strip)
            Skipping invalid Content Security Policy #{directive}: "#{source}".
            Directive values must not contain whitespace or semicolons.
            Please use multiple arguments or other directive methods instead.
          MSG
          next
        end
        @directives[directive] << source
      end

      @directives[directive].delete(:none) if @directives[directive].count > 1
    end

    def extendable?(directive)
      EXTENDABLE_DIRECTIVES.include?(directive)
    end

    def valid_extension?(extension)
      extension.is_a?(Hash)
    end
  end
def build(theme_id, base_url:, path_info: "/", report_only: false)
    builder = Builder.new(context: @context, base_url: base_url, report_only: report_only)

    @context.extensions.theme_extensions(theme_id).each { |extension| builder << extension }
    @context.extensions.plugin_extensions.each { |extension| builder << extension }
    builder << @context.extensions.site_setting_extension

    builder.build
  end
end
