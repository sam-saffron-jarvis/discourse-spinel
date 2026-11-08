# frozen_string_literal: true
require_relative 'client_loading_admin_source'
require_relative 'client_highlight_source'
module ClientHighlightBootstrap
  def self.bind(root, events)
    raise ArgumentError, 'highlight serving-root changed' unless root == RequestAssetCapability::ROOT
    @root, @events = root, events
    @files ||= {}
    @reads ||= 0
    nil
  end
  def self.vendored_path(relative)
    raise ArgumentError, 'unsupported HighlightJs vendor relative path' unless relative == 'highlightjs/languages'
    root = @root
    raise 'HighlightJs root not acquired' unless root.is_a?(String)
    File.join(root, 'vendor/runtime_node_modules', relative)
  end
  def self.asset_url_salt
    value = ListHeadImages.configuration.value('asset_url_salt')
    raise TypeError, 'HighlightJs asset salt not nullable String' unless value.nil? || value.is_a?(String)
    value
  end
  def self.read_language(path)
    base = vendored_path('highlightjs/languages') + '/'
    raise ArgumentError, 'HighlightJs language escaped acquired root' unless path.start_with?(base) && path.delete_prefix(base).match?(/\A[a-zA-Z0-9_+\-]+\.min\.js\z/)
    root = @root
    raise 'HighlightJs root not acquired' unless root.is_a?(String)
    RequestAssetServing.verified_member!(root, path) if File.exist?(path)
    # Preserve actual File.read ENOENT and the source bundle rescue. Existing
    # members must be proved before reading, not admitted from observed output.
    value = File.read(path)
    @reads = reads + 1
    files[path.delete_prefix(base)] = Digest::SHA256.hexdigest(value)
    value
  end
  def self.files; @files ||= {}; end
  def self.reads; @reads || 0; end
  def self.site; CategoryCacheApplication::RailsMultisite::ConnectionManagement.current_db; end
  def self.source_path; RequestHighlightJs.path; end
  def self.source_version(languages); RequestHighlightJs.version(languages); end
  def self.source_cache; RequestHighlightJs.cache; end
  def self.path
    events = @events
    raise 'HighlightJs events not bound' unless events.is_a?(Array)
    events << 'highlight_js_acquisition'
    value = source_path
    value += '-wrong' if ENV.fetch('FIDELITY_CLIENT_PATH_FAULT', '') == 'wrong-highlight-path'
    @path = value
    events << 'highlight_js_returned'
    value
  end
  def self.path_value; @path; end
  def self.admin_value; @admin_value; end
  def self.record_admin(value)
    raise TypeError, 'loading_admin? result not Boolean' unless value == true || value == false
    @admin_value = value
    value
  end
end
module ClientHighlightViewProtocol
  def client_side_setup_data
    ClientHighlightBootstrap.bind(@asset_source_root, @events)
    asset_version_client_side_setup_data
  end
  def expected_body_events
    expected_asset_version_bus_events + ['loading_admin_returned', 'highlight_js_acquisition', 'highlight_js_returned', 'svg_sprite_acquisition']
  end
  def loading_admin?
    @events << 'loading_admin_acquisition'
    value = source_loading_admin?
    value = !value if ENV.fetch('FIDELITY_CLIENT_PATH_FAULT', '') == 'wrong-admin'
    value = ClientHighlightBootstrap.record_admin(value)
    @events << 'loading_admin_returned'
    value
  end
  def client_setup_svg_path(id)
    @events << 'svg_sprite_acquisition'
    raise HtmlRenderingBoundary, 'actual loading-admin and HighlightJs path acquired; SVG sprite acquisition pending'
  end
  def client_highlight_stage_observation
    record = asset_version_bus_stage_observation
    owner = controller.class.name
    value = ClientHighlightBootstrap.admin_value
    raise 'loading_admin? differs from genuine controller owner' unless value == (owner.split('::').first == 'Admin')
    languages = SiteSetting.highlighted_languages
    raise TypeError, 'HighlightJs setting not String' unless languages.is_a?(String)
    cache = ClientHighlightBootstrap.source_cache[ClientHighlightBootstrap.site]
    raise 'HighlightJs source cache missing' unless cache.is_a?(Hash) && cache[:lang_string] == languages
    expected_files = languages.split('|').map { |lang| lang + '.min.js' }.select { |name| File.file?(File.join(ClientHighlightBootstrap.vendored_path('highlightjs/languages'), name)) }.uniq.sort
    raise 'HighlightJs language coverage missing' unless ClientHighlightBootstrap.files.keys.sort == expected_files
    digest = cache[:digest]
    reads = ClientHighlightBootstrap.reads
    warm = ClientHighlightBootstrap.source_version(languages)
    raise 'HighlightJs warm source memo identity changed' unless digest.equal?(warm) && ClientHighlightBootstrap.reads == reads
    path = ClientHighlightBootstrap.path_value
    raise 'wrong acquired HighlightJs path' unless path == "/highlight-js/#{Discourse.current_hostname}/#{digest}.js"
    record[:client_highlight] = {disable_custom_css: value, controller_class: owner, languages: languages, salt: ClientHighlightBootstrap.asset_url_salt, version: digest, path: path, files: ClientHighlightBootstrap.files, reads: reads, warm_digest_identity: true}
    record
  end
end
class ListBodyContext
  include ClientLoadingAdminSource
  include ClientHighlightViewProtocol
  def observation; client_highlight_stage_observation; end
end
