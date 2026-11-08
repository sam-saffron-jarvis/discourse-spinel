# frozen_string_literal: true
root = ARGV.fetch(0)
log_root = ARGV.fetch(1)
raise "unit log fixture must be owned/private" unless File.directory?(log_root) && File.stat(log_root).uid == Process.euid && File.stat(log_root).mode & 0o077 == 0
roots = ["#{root}/frontend/discourse/dist/assets", "#{root}/frontend/discourse/scripts"]
manifest = JSON.parse(File.read("#{root}/frontend/discourse/dist/manifest/manifest.json"))
chunks = PortableEmberAssetGraph.script_chunks(manifest)
asset_map = PortableEmberAssetGraph.import_map(manifest)
EmberAssets.import_map = asset_map
asset_reads = chunks.values.flatten.uniq.map do |name|
  data = File.binread("#{roots.first}/#{name}.js")
  [name, data.bytesize, Digest::SHA256.hexdigest(data)]
end
actual_nonces = []
[
  [false, true, "/unit-root", "https://cdn.unit.invalid"],
  [true, true, "/unit-root", "https://cdn.unit.invalid"],
  [false, false, "/unit&\"<root", "https://changed.unit.invalid"],
  [true, false, nil, nil],
].each do |unit_staff, cacheable, url_root, cdn|
  settings = UnitAssetSettings.new(url_root, cdn, false, nil, nil)
  helper = new_layout_asset_helper(settings, roots, "2-unit-layout", nil, chunks, unit_staff, cacheable)
  # These are UNIT settings/hosts/extensions, NOT real Site/theme acquisitions.
  # Both headers are genuinely constructed by Default -> Builder -> serializer.
  csp_settings = UnitCspSettings.new(cacheable, "/unit-csp-report", true, false, "'sha256-dW5pdA=='|https://ignored.unit.invalid")
  csp_context = UnitCspContext.new(csp_settings, settings, ["embedded.unit.invalid"],
    [{script_src: ["'nonce-unit-extension'", "'unsafe-inline'", "'bad source'"]}],
    [{object_src: ["/unit-object"]}], File.join(log_root, "fragment-#{unit_staff}-#{cacheable}.log"))
  built_policies = {
    "Content-Security-Policy" => unit_build_csp(csp_context, "https://forum.unit.invalid", false),
    "Content-Security-Policy-Report-Only" => unit_build_csp(csp_context, "https://forum.unit.invalid", true),
  }
  built_policies.each { |name, value| helper.response.headers[name] = value }
  raise "composition used a supplied unit CSP string" unless built_policies.values.all? { |policy| policy.include?("script-src 'strict-dynamic' 'wasm-unsafe-eval' 'report-sample'") && policy.include?("object-src https://forum.unit.invalid/unit-object") && !policy.include?("ignored.unit.invalid") && !policy.include?("'unsafe-inline'") }
  raise "composed enforced/report upgrade semantics changed" unless built_policies["Content-Security-Policy"].start_with?("upgrade-insecure-requests; ") == cacheable && !built_policies["Content-Security-Policy-Report-Only"].include?("upgrade-insecure-requests")
  helper.asset_import_map = asset_map
  unit_plugin_assets = []
  if unit_staff
    unit_plugin_assets << {name: "js/browser-detect", importmap_name: "discourse/plugins/unit-plugin",
                           plugin: UnitPluginMetadata.new("unit-plugin"), external_plugin_imports: ["unit-plugin", "unit-missing"]}
    helper.unit_theme_assets = [{external_plugin_imports: ["unit-missing", "unit-theme-only"]}]
  end
  importmap_rendered = helper.render_importmap_fragment(unit_plugin_assets)
  raise "import-map fragment trust lost" unless unit_fragment?(importmap_rendered)
  importmap_text = importmap_rendered.to_s
  importmap_json = importmap_text[/<script type="importmap" nonce="[^"]+">(.*)<\/script>/m, 1]
  raise "concrete import-map script missing" unless importmap_json
  raise "import-map JSON was escaped" if importmap_json.include?("&quot;")
  imports = JSON.parse(importmap_json)["imports"]
  raise "import-map object changed type" unless imports.is_a?(Hash)
  asset_map.each do |stable, real|
    real_url = helper.script_asset_path(real)
    stable_url = real_url.sub(File.basename(real), File.basename(stable))
    raise "core stable import mapping lost" unless imports[stable_url] == real_url
  end
  if unit_staff
    raise "available unit plugin alias lost" unless imports["discourse/plugins/unit-plugin?"] == imports["discourse/plugins/unit-plugin"]
    raise "original optional plugin stub lost" unless imports["discourse/plugins/unit-missing?"].include?("new Proxy")
    raise "original required plugin stub lost" unless imports["discourse/plugins/unit-missing"].include?("throw new Error")
    raise "unit theme import lost" unless imports["discourse/plugins/unit-theme-only?"].include?("new Proxy")
  else
    raise "core import map fabricated plugin data" unless imports.length == asset_map.length
  end
  # Supplied UNIT serialized strings only, never fake Site/settings preloads.
  if cacheable || unit_staff
    unit_values = {"unit-serialized" => JSON.generate({"unit" => "</script><script>unit only</script>\u2028雪&"}),
                   "unit-null" => nil}
    unit_values["unit-invalid-utf8"] = "prefix\xFFsuffix".dup.force_encoding("UTF-8") if !cacheable
    helper.application_layout_preloader = UnitFragmentPreloader.new(unit_values)
  end
  rendered = helper.render_asset_fragment
  raise "wrong final trusted fragment type" unless unit_fragment?(rendered)
  text = rendered.to_s
  raise "missing actual browser preload link" unless text.start_with?('<link rel="preload"') || text.start_with?('    <link rel="preload"')
  raise "trusted HTML was escaped as text" if text.include?("&lt;script") || text.include?("&lt;link rel=")
  if url_root && url_root.include?("&")
    # The literal ERB String expression is escaped. Existing trusted helper
    # HTML retains original URL interpolation semantics; no false hardening.
    raise "ordinary URL expression was not escaped" unless text.include?("/unit&amp;&quot;&lt;root/assets/js/browser-update-")
  end
  expected_count = chunks["discourse"]
  expected_count = (expected_count + chunks["admin/compat-modules"]).uniq if unit_staff
  raise "module ordering/count changed" unless text.scan('<link rel="modulepreload"').length == expected_count.length
  raise "ordinary script ordering changed" unless text.index('rel="preload"') < text.index('<script defer') && text.index('<script defer') < text.index('<link rel="modulepreload"')
  raise "resource-preload effect omitted or broadened" unless helper.asset_preload_links.length == 1 && helper.asset_preload_links.first.include?("browser-detect-")
  marker = helper.response.headers[Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER]
  raise "nonce marker missing from source composition" unless marker && text.include?(marker)
  data_fragment = helper.render_preload_fragment
  raise "lost preload fragment trust" unless unit_fragment?(data_fragment)
  data_text = data_fragment.to_s
  json_text = data_text[/<script type="application\/json" id="data-preloaded">(.*)<\/script>/m, 1]
  raise "preloaded JSON source script missing" unless json_text
  raise "raw JSON was HTML-escaped" if json_text.include?("&quot;")
  parsed_unit_data = JSON.parse(json_text)
  raise "concrete preload output type changed" unless parsed_unit_data.is_a?(Hash)
  raise "script closer escaped incorrectly" unless data_text.scan("</script>").length == 1
  raise "literal line separator leaked into script" if json_text.include?("\u2028")
  preloader = helper.application_layout_preloader
  if preloader
    raise "preloaded data acquired incorrectly" unless preloader.reads == 1
    raise "unit serialized values changed type" unless parsed_unit_data["unit-serialized"].is_a?(String) && parsed_unit_data["unit-null"] == ""
  else
    raise "nil preloader was fabricated" unless parsed_unit_data.empty?
  end
  env = helper.request.env
  headers = helper.response.headers
  body = [importmap_text, text, data_text]
  app = lambda { |_env| [200, headers, body] }
  status, headers, final_parts = Middleware::CspScriptNonceInjector.new(app).call(env)
  final = final_parts[1]
  nonce = final[/nonce="([^"]+)"/, 1]
  raise "wrong generated nonce" unless nonce && nonce.match?(/\A[a-zA-Z0-9]{25}\z/)
  raise "reused nonce across unit contexts" if actual_nonces.include?(nonce)
  actual_nonces << nonce
  raise "nonce not applied throughout rendered fragment" unless final.scan(/nonce="[^"]+"/).all? { |attribute| attribute == "nonce=\"#{nonce}\"" }
  raise "CSP agreement changed" unless headers["Content-Security-Policy"].include?("script-src 'nonce-#{nonce}' ")
  built_policies.each do |name, policy|
    raise "built header/body nonce agreement changed" unless headers[name] == policy.sub("script-src ", "script-src 'nonce-#{nonce}' ")
  end
  raise "composition lost actual logger effects" unless csp_context.warnings.lines.length == 2 && csp_context.warnings.lines.all? { |line| line.start_with?("WARN: Skipping invalid Content Security Policy script_src:") }
  csp_warnings = csp_context.warnings
  csp_context.close
  raise "header marker leaked" if headers.key?(Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER)
  raise "body replacement identity changed" unless final_parts.equal?(body) == !cacheable
  raise "CSP rewriting changed preload JSON" unless final_parts[2] == data_text
  raise "import-map nonce/CSP disagree" unless final_parts[0].include?("nonce=\"#{nonce}\"")
  deliveries = []
  if url_root.nil? && cdn.nil?
    # Real URLs extracted from the rendered source spans are consumed by the
    # actual read-only asset component, not merely compared as URL strings.
    linked = final.scan(/(?:href|src)="([^"]+)"/).map { |match| match.first }
    linked += imports.values.select { |url| url.is_a?(String) && url.start_with?("/assets/") }
    asset_app = lambda { |_env| [418, {"Content-Type" => "text/plain"}, ["unit unexpected fallback"]] }
    asset_server = new_unit_asset_response(asset_app, roots, "2-unit-layout")
    linked.uniq.each do |url|
      asset_status, asset_headers, asset_body = asset_server.call({"REQUEST_METHOD" => "GET", "PATH_INFO" => url})
      raise "rendered asset URL did not return genuine 200" unless asset_status == 200
      content = asset_body.join
      raise "rendered asset response headers disagree" unless asset_headers["Content-Length"] == content.bytesize.to_s && asset_headers["Content-Type"] == "text/javascript"
      deliveries << {url: url, headers: asset_headers, bytes: content.bytesize, sha256: Digest::SHA256.hexdigest(content)}
    end
    raise "rendered asset graph delivery omitted" unless deliveries.length >= asset_map.length
  end
  puts JSON.generate({unit_staff_input: unit_staff, cacheable_unit_env: cacheable,
    built_policies: built_policies, csp_warnings: csp_warnings, status: status, text: final.gsub(nonce, "UNIT_NORMALIZED_NONCE"), preload_fragment: data_text,
    importmap_fragment: final_parts[0].gsub(nonce, "UNIT_NORMALIZED_NONCE"), delivered_assets: deliveries,
    headers: headers.transform_values { |value| value.gsub(nonce, "UNIT_NORMALIZED_NONCE") },
    resource_preloads: helper.asset_preload_links, trusted_result: true, modules: expected_count.length})
end
missing_settings = UnitAssetSettings.new(nil, nil, false, nil, nil)
missing = new_layout_asset_helper(missing_settings, ["#{root}/unit-nonexistent-assets"], "2-unit-layout", nil, chunks, false, true)
begin
  missing.render_asset_fragment
  raise "layout fabricated missing asset"
rescue StandardError => error
  raise unless missing_asset_error?(error)
  raise "missing asset caused resource effects" unless missing.asset_preload_links.nil?
  raise "missing asset generated nonce before URL acquisition" if missing.response.headers.key?(Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER)
end
missing_import = new_layout_asset_helper(missing_settings, ["#{root}/unit-nonexistent-assets"], "2-unit-layout", nil, chunks, false, true)
missing_import.asset_import_map = asset_map
begin
  missing_import.render_importmap_fragment([])
  raise "import map fabricated missing assets"
rescue StandardError => error
  raise unless missing_asset_error?(error)
  raise "import map invented preload resource effects" unless missing_import.asset_preload_links.nil?
  # Unlike the asset span, original import-map nonce executes BEFORE lookup.
  raise "source import-map nonce ordering lost" unless missing_import.response.headers.key?(Middleware::CspScriptNonceInjector::PLACEHOLDER_HEADER)
end
puts JSON.generate({genuine_asset_reads: asset_reads})
puts "PASS concrete original ERB fragment/typed trust/file resolver/source helpers/CSP/resource/missing integration; NOT a page"
