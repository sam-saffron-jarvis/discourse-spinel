# frozen_string_literal: true
# TEST-only original source HTML observation. Never a candidate/native input.
require_relative "oracle_isolation"
at_exit { FidelityOracleIsolation.cleanup_vips! }
require "fileutils"
require "rack/mock"

output = ENV.fetch("FIDELITY_HTML_OUTPUT_DIRECTORY")
FileUtils.mkdir_p(output)
raise "no-plugin policy missing" unless ENV.fetch("LOAD_PLUGINS") == "0"
raise "readonly PG policy missing" unless ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
root = File.realpath(".")
plugin_root = File.join(root, "plugins") + "/"
compiled_plugins = []
trace = TracePoint.new(:script_compiled) do |event|
  path = event.instruction_sequence&.path
  next unless path && File.expand_path(path).start_with?(plugin_root)
  compiled_plugins << path
  raise "core-only HTML loaded a plugin: #{path}"
end
begin
  trace.enable
  require File.expand_path("config/environment.rb")
  raise "plugin activation is not disabled" if GlobalSetting.load_plugins? || !Discourse.plugins.empty?
  connection = ActiveRecord::Base.connection
  raise "wrong database" unless connection.select_value("SELECT current_database()") == "discourse_development"
  raise "wrong PG port" unless connection.select_value("SELECT inet_server_port()") == 5499
  raise "writable PG" unless connection.select_value("SHOW default_transaction_read_only") == "on"
  manifest_path = File.join(EmberAssets.dist_dir, "manifest/manifest.json")
  raise "real frontend manifest absent" unless File.file?(manifest_path)
  rows = []
  ["/latest", "/latest?page=1"].each_with_index do |path, index|
    url = URI.parse(Discourse.base_url + path)
    host = url.host + (url.default_port == url.port ? "" : ":#{url.port}")
    readonly_errors = []
    readonly_trace = TracePoint.new(:raise) do |event|
      error = event.raised_exception
      readonly_errors << {message: error.message, backtrace: error.backtrace} if error.is_a?(ActiveRecord::ReadOnlyError)
    end
    response = nil
    original_request = lambda do
      response = Rack::MockRequest.new(Rails.application).get(url.to_s,
      "HTTP_HOST" => host, "REMOTE_ADDR" => "127.0.0.1", "HTTP_ACCEPT" => "text/html",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36")
    end
    begin
      readonly_trace.enable
      if ENV.fetch("FIDELITY_HTML_PREVENT_AR_WRITES", "0") == "1"
        ActiveRecord::Base.while_preventing_writes { original_request.call }
      else
        original_request.call
      end
    ensure
      readonly_trace.disable
    end
    File.write(File.join(output, "original-#{index}-readonly-errors.json"), JSON.pretty_generate(readonly_errors) + "\n")
    File.binwrite(File.join(output, "original-#{index}.html"), response.body)
    document = Nokogiri::HTML5(response.body)
    preloaded = document.at_css("#data-preloaded")
    row = {path: path, status: response.status, headers: response.headers.to_h,
      body_sha256: Digest::SHA256.hexdigest(response.body), body_bytes: response.body.bytesize,
      title: document.at_css("title")&.text,
      preloaded_keys: preloaded ? JSON.parse(preloaded.text).keys.sort : [],
      script_urls: document.css("script[src]").map { |node| node["src"] },
      stylesheet_urls: document.css('link[rel="stylesheet"]').map { |node| node["href"] },
      module_preload_urls: document.css('link[rel="modulepreload"]').map { |node| node["href"] }}
    rows << row
    File.write(File.join(output, "original-responses.json"), JSON.pretty_generate(rows) + "\n")
    puts "FIDELITY_ORIGINAL_HTML " + JSON.generate(row)
    raise "original HTML did not render a genuine full page" unless response.status == 200 && preloaded && !row[:script_urls].empty?
  end
  File.write(File.join(output, "original-attestation.json"), JSON.pretty_generate({
    root: root, original_source_pin: ENV.fetch("FIDELITY_HTML_SOURCE_PIN"),
    manifest_path: manifest_path, manifest_sha256: Digest::SHA256.file(manifest_path).hexdigest,
    compiled_plugin_sources: compiled_plugins, loaded_plugins: Discourse.plugins.map(&:name),
    actual_git_version: GitUtils.git_version,
    stylesheet_cache_rows: StylesheetCache.count,
    native_html_executed: false, browser_rendered: false, page_accepted: false,
  }) + "\n")
rescue Exception => error
  File.write(File.join(output, "original-error.json"), JSON.pretty_generate({
    error_class: error.class.name, error: error.message, backtrace: error.backtrace,
    native_html_executed: false, browser_rendered: false, page_accepted: false,
  }) + "\n")
  raise
ensure
  trace.disable
end
