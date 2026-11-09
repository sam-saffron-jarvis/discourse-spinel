# frozen_string_literal: true
require_relative 'client_meta_declarations'
require_relative 'client_meta_storage_source'
require_relative 'client_meta_bus_source'
require_relative 'client_meta_source'
require_relative 'emitted/runtime/json_builder'
# Existing CookieJar's [] uses "" for .to_s-only consumers. These source
# palette helpers distinguish missing from present-empty, so read real presence.
class ActionController::CookieJar
  def client_meta_nullable_read(key)
    name = key.to_s
    @inbound[name] if @inbound.key?(name)
  end
end
class ClientMetaCookieView
  def initialize(jar); @jar = jar; end
  def [](key); @jar.client_meta_nullable_read(key); end
end
class CategoryCacheLease
  def client_meta_read_command?(command)
    command == ['GET', "__mb_backlog_id_n_/file-change$|$#{namespace}"]
  end
  def authorize_client_meta_read(command)
    check!(@host, @port)
    raise ArgumentError, 'client meta file-change read scope' unless client_meta_read_command?(command) && Thread.current == Thread.main
    @lock.synchronize { @client_meta_file_reads = client_meta_file_reads + 1 }
    true
  end
  def client_meta_file_reads; @client_meta_file_reads || 0; end
end
module ClientMetaRead
  def self.environment; Rails.env; end
  def self.error_reporting
    value = ListHeadImages.configuration.value('enable_js_error_reporting')
    raise TypeError, 'client setup error reporting not nullable Boolean' unless value.nil? || value == true || value == false
    value
  end
  def self.all_icons(id)
    SvgBundleBootstrap.source_icons(id)
  end
  def self.last_id(channel)
    channel = '/wrong/file-change' if ENV.fetch('FIDELITY_CLIENT_META_FAULT', '') == 'wrong-file-channel'
    raise ArgumentError, 'client meta file-change source channel' unless channel == '/file-change'
    CategoryCacheBootstrap.bus.last_id(channel)
  end
  def self.serialize_meta(id, data)
    raise ArgumentError, 'unacquired meta id/attributes profile' unless id == 'data-discourse-setup' && data.is_a?(Hash)
    text = '<meta id="' + ActionView::ViewHelpers.html_escape(id) + '"'
    data.each do |key, value|
      raise ArgumentError, 'unacquired client meta key' unless ClientMetaDeclarations::KEYS.include?(key)
      next if value.nil?
      valid = value.is_a?(String) || value == true || value == false || value.is_a?(Integer) || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
      raise TypeError, 'unacquired client meta data value type' unless valid
      raw = value.is_a?(String) ? value : JsonBuilder.escape_html_entities(JSON.generate(value))
      text += ' data-' + key.to_s.tr('_', '-') + '="' + ActionView::ViewHelpers.html_escape(raw) + '"'
    end
    text + '>'
  end
end
class ClientSetupTagBuilder
  def meta(id:, data:)
    text = ClientMetaRead.serialize_meta(id, data)
    text = text.gsub('&quot;', '"') if ENV.fetch('FIDELITY_CLIENT_META_FAULT', '') == 'unescaped-json'
    text = text.sub('data-svg-sprite-path=', 'data-wrong-svg-path=') if ENV.fetch('FIDELITY_CLIENT_META_FAULT', '') == 'wrong-attribute'
    ActionView::HtmlFragment.new(text)
  end
end
module ClientMetaViewProtocol
  def expected_body_events
    values = expected_client_highlight_events + ['svg_cache_version_acquisition']
    unless SvgBundleBootstrap.version_hit_on_entry
      values += ['svg_cache_icons_acquisition', 'svg_cache_settings_acquisition', 'svg_settings_hash_acquisition']
    end
    values + ['svg_cache_icons_acquisition', 'client_setup_data_returned', 'client_setup_meta_returned']
  end
  def cookies; @client_meta_cookies ||= ClientMetaCookieView.new(controller.cookies); end
  def user_scheme_id
    raise ArgumentError, 'unsupported client setup user/cookie palette' unless current_user.nil? && request.env['HTTP_COOKIE'].nil?
    value = cookies[:color_scheme_id]
    return if value.nil?
    raise ArgumentError, 'unsupported client setup selected palette'
  end
  def user_dark_scheme_id
    raise ArgumentError, 'unsupported client setup user/cookie palette' unless current_user.nil? && request.env['HTTP_COOKIE'].nil?
    value = cookies[:dark_scheme_id]
    return if value.nil?
    raise ArgumentError, 'unsupported client setup selected dark palette'
  end
  def normalized_safe_mode; raise ArgumentError, 'unsupported client setup safe-mode normalization profile'; end
  def client_side_setup_data
    value = client_setup_without_meta_completion
    raise TypeError, 'client setup consumer must receive Hash' unless value.is_a?(Hash)
    value[:user_color_scheme_id] = 0 if ENV.fetch('FIDELITY_CLIENT_META_FAULT', '') == 'wrong-user-scheme'
    @client_meta_data = value
    @events << 'client_setup_data_returned'
    value
  end
  def client_meta_layout_boundary
    raise 'layout executed before completed body' unless @body_returned
    @events << 'layout_render'
    @body_output = +''
    @output_buffer = self
    begin
      render_application_layout { |slot| head_yield_capability(slot) }
      @events << 'client_setup_meta_returned'
      raise HtmlRenderingBoundary, 'actual client setup meta consumer returned; remaining layout acquisition pending'
    ensure
      close_request_assets
    end
  end
  def client_meta_stage_observation
    puts 'FIDELITY_CLIENT_META_EVENTS ' + JSON.generate({actual: @events, expected: expected_body_events})
    record = svg_bundle_stage_observation
    data = @client_meta_data
    raise 'client setup data not acquired' unless data.is_a?(Hash)
    raise 'client setup data key order changed' unless data.keys.first(ClientMetaDeclarations::FIRST_KEYS.size) == ClientMetaDeclarations::FIRST_KEYS
    raise 'client setup SVG path differs' unless data[:svg_sprite_path] == SvgBundleBootstrap.path
    raise 'client setup asset version differs' unless data[:asset_version] == AssetVersionGraphBootstrap.digest
    raise 'client setup default user palette differs' unless data[:user_color_scheme_id] == (user_scheme_id || -1) && data[:user_dark_scheme_id] == (user_dark_scheme_id || -1)
    raise 'client setup nullable staff changed' unless data[:is_staff] == staff?
    icon_key = 'icons_' + ListThemeCompilerSource.transform_ids(theme_id).join(',')
    raise 'client setup development icon list changed' unless data[:svg_icon_list] == CategoryCacheBootstrap.svg_cache.svg_values[icon_key]
    lease = CategoryCacheBootstrap.lease
    raise 'client setup genuine file-change read missing' unless lease.client_meta_file_reads > 0
    direct_id = CategoryCacheBootstrap.bus.backend_instance.last_id(CategoryCacheBootstrap.bus.encode_channel_name('/file-change'))
    raise 'client setup source MessageBus last_id changed' unless data[:mb_last_file_change_id] == direct_id
    normalized = data.dup
    normalized[:environment] = data[:environment].to_s
    expected = ClientMetaRead.serialize_meta('data-discourse-setup', normalized)
    prefix = prefix_snapshot
    index = prefix.index('<meta id="data-discourse-setup"')
    raise 'client setup actual meta tag missing' if index.nil?
    actual = prefix[index..-1]
    raise 'client setup meta escaping/output changed' unless actual == expected
    record[:client_meta] = {keys: normalized.keys, data: normalized, html: actual, bytes: actual.bytesize, file_change_read: true, nullable_staff_preserved: true, environment_immediate_string_consumer: true, generic_setup_hash_api_supported: false}
    record
  end
end
class ListBodyContext
  include ClientMetaSource
  include ClientMetaViewProtocol
  def layout_boundary; client_meta_layout_boundary; end
  def observation; client_meta_stage_observation; end
end
