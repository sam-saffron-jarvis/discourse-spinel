# frozen_string_literal: true
require 'cgi'
require_relative 'body_layout_read_source'
require_relative 'body_layout_source'
require_relative 'body_layout_template'
require_relative 'body_splash_template'
module BodyLayoutRead
  def self.source_upload; SvgSettingsRead.upload('splash_screen_image'); end
  def self.checked_upload
    value = source_upload
    raise ArgumentError, 'unsupported nonempty splash upload profile' unless value.nil?
    value
  end
  def self.note_cookie(key)
    @auth_cookie_reads = auth_cookie_reads + 1 if key == :authentication_data
    nil
  end
  def self.auth_cookie_reads; @auth_cookie_reads || 0; end
end
module BodyLayoutViewProtocol
  def expected_body_events
    expected_client_meta_events + ['config_environment_acquisition', 'config_environment_returned', 'authentication_data_acquisition', 'authentication_data_returned', 'body_classes_acquisition', 'body_classes_returned', 'splash_predicate_acquisition', 'splash_predicate_returned', 'splash_partial_acquisition', 'splash_partial_returned', 'stylesheet_effect_boundary']
  end
  def client_meta_markup(prefix, index)
    finish = prefix.index('>', index)
    raise 'client setup meta close missing' if finish.nil?
    prefix[index..finish]
  end
  def discourse_config_environment(testing: false)
    @events << 'client_setup_meta_returned'
    @events << 'config_environment_acquisition'
    value = source_config_environment(testing: testing)
    value += ' ' if ENV.fetch('FIDELITY_BODY_LAYOUT_FAULT', '') == 'wrong-config-json'
    raise TypeError, 'config environment JSON not String' unless value.is_a?(String)
    @body_config_json = value
    @events << 'config_environment_returned'
    value
  end
  def u(value)
    value = CGI.escape(value).gsub('+', '%20')
    value = value.gsub('%7B', '{') if ENV.fetch('FIDELITY_BODY_LAYOUT_FAULT', '') == 'wrong-uri-escape'
    value
  end
  def authentication_data
    @events << 'authentication_data_acquisition'
    raise ArgumentError, 'unsupported authentication cookie/user profile' unless current_user.nil? && request.env['HTTP_COOKIE'].nil?
    before = BodyLayoutRead.auth_cookie_reads
    value = source_authentication_data
    raise 'authentication source cookie read skipped' unless BodyLayoutRead.auth_cookie_reads == before + 1
    @body_authentication = value
    @events << 'authentication_data_returned'
    value
  end
  def body_classes
    @events << 'body_classes_acquisition'
    raise ArgumentError, 'unsupported nonanonymous/categorized body profile' unless current_user.nil? && @category.nil?
    value = source_body_classes
    value += ' fabricated-class' if ENV.fetch('FIDELITY_BODY_LAYOUT_FAULT', '') == 'wrong-body-class'
    @body_class_value = value
    @events << 'body_classes_returned'
    value
  end
  def include_splash_screen?
    @events << 'splash_predicate_acquisition'
    value = source_include_splash_screen?
    value = !value if ENV.fetch('FIDELITY_BODY_LAYOUT_FAULT', '') == 'wrong-splash-predicate'
    @body_splash_enabled = value
    @events << 'splash_predicate_returned'
    value
  end
  def custom_splash_screen_enabled?
    BodyLayoutRead.checked_upload
    source_custom_splash_screen_enabled?
  end
  def light_color_hex_for_name(name); ListLayoutColors.hex_for_name(name, scheme_id); end
  def dark_color_hex_for_name(name); ListLayoutColors.hex_for_name(name, dark_scheme_id); end
  def splash_screen_image_animated?; raise ArgumentError, 'unsupported nonempty splash image animation'; end
  def splash_screen_image_data_uri(dark: false); raise ArgumentError, 'unsupported nonempty splash image URI'; end
  def splash_screen_inline_svg; raise ArgumentError, 'unsupported nonempty splash image inline SVG'; end
  def render(name = nil, partial: nil, opts: nil)
    if partial == 'common/discourse_stylesheet'
      # TEST-only quiescence before inherited cross-cache warm observers.
      # All real queued work must finish; never seed/skip a publication.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
      loop do
        queued = 0
        finished = 0
        CategoryCacheBootstrap.scheduler.stats.each do |entry|
          queued += entry[1][:queued]
          finished += entry[1][:finished]
        end
        break if queued == finished
        raise 'body layout actual deferred work fence missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.01
      end
      @events << 'stylesheet_effect_boundary'
      raise HtmlRenderingBoundary, 'actual config/auth/body/splash returned; stylesheet effects prohibited'
    end
    return render_before_body_tail(name, partial: partial, opts: opts) unless partial == 'common/discourse_splash'
    @events << 'splash_partial_acquisition'
    value = capture_list_body { render_splash_partial }
    value = '' if ENV.fetch('FIDELITY_BODY_LAYOUT_FAULT', '') == 'drop-splash'
    @body_splash_output = value.to_s
    @events << 'splash_partial_returned'
    layout_fragment(value)
  end
  def body_layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @body_output = +''
    @output_buffer = self
    begin
      render_application_layout { |slot| head_yield_capability(slot) }
      raise 'body layout stylesheet boundary unexpectedly returned'
    ensure
      close_request_assets
    end
  end
  def body_layout_stage_observation
    record = client_meta_stage_observation
    config = @body_config_json
    raise 'body layout actual config missing' unless config.is_a?(String)
    parsed = JSON.parse(config)
    raise 'body layout config source version differs' unless parsed['APP']['version'] == ListLayoutSource::VERSION_STRING + ' ' + PortableGitVersion.read(PortableGitVersion.application_root)
    raise 'body layout config source environment differs' unless parsed['environment'] == ENV.fetch('RAILS_ENV') && parsed['rootURL'] == Discourse.base_path
    prefix = prefix_snapshot
    raise 'body layout JSON/URI serialization changed' unless config == source_config_environment && prefix.include?('<meta name="discourse/config/environment" content="' + CGI.escape(config).gsub('+', '%20') + '" />')
    before = BodyLayoutRead.auth_cookie_reads
    raise 'body layout authentication nil/memo changed' unless @body_authentication.nil? && instance_variable_defined?(:@authentication_data) && source_authentication_data.nil? && source_authentication_data.nil? && BodyLayoutRead.auth_cookie_reads == before
    raise 'body layout actual body class changed' unless @body_class_value == BodyLayoutRead.extra_body_classes.to_a.join(' ') && prefix.include?('<body class="' + ERB::Util.html_escape(@body_class_value) + '">')
    enabled = ENV.fetch('RAILS_ENV') != 'test'
    raise 'body layout actual splash predicate changed' unless @body_splash_enabled == enabled
    splash = @body_splash_output
    raise 'body layout actual splash missing' unless enabled && splash.is_a?(String) && !splash.empty? && prefix.include?(splash)
    raise 'body layout splash structure changed' unless splash.include?('<section id="d-splash">') && splash.scan('class="dots"').size == 5 && splash.include?('nonce="' + csp_nonce_placeholder + '"')
    normalized = splash.gsub(csp_nonce_placeholder, '[genuine-random-nonce]')
    raise 'body layout stylesheet partial already rendered' if prefix.include?('<script type="application/json" id="data-preloaded">')
    record[:body_layout] = {config_json: config, config: parsed, authentication_nil_memo: true, body_class: @body_class_value, splash_enabled: enabled, splash_bytes: splash.bytesize, splash_sha256_normalized: Digest::SHA256.hexdigest(normalized), splash_html_normalized: normalized, custom_image_nil: BodyLayoutRead.checked_upload.nil?, stylesheet_called_before_effects: true, stylesheet_acquired: false, full_layout_completed: false}
    record
  end
end
class ListBodyContext
  include BodyLayoutSource
  include BodySplashTemplate
  include BodyLayoutTemplate
  include BodyLayoutViewProtocol
  def layout_boundary; body_layout_boundary; end
  def observation; body_layout_stage_observation; end
end
