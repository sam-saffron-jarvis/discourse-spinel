# frozen_string_literal: true
require "json"
log_root = ARGV.fetch(0)
raise "unit log fixture must be owned/private" unless File.directory?(log_root) && File.stat(log_root).uid == Process.euid && File.stat(log_root).mode & 0o077 == 0
cases = [
  ["basic", false, nil, false, false, nil, nil, false, nil, nil],
  ["https-report-frame", true, "/unit-csp-report", true, false, "/unit-root", "https://cdn.unit.invalid", false, nil, nil],
  ["s3-assets-embed-any", true, "https://reports.unit.invalid/csp", true, true, "/other-root", "https://cdn.unit.invalid", true, "https://s3.unit.invalid", "https://asset-cdn.unit.invalid"],
  ["s3-empty-fallback", false, "\0 \t", true, false, nil, nil, true, "https://s3.unit.invalid", ""],
]
cases.each do |name, https, report_uri, restrict, embed_any, root, cdn, use_s3, s3, s3_asset|
  settings = UnitCspSettings.new(https, report_uri, restrict, embed_any, "'sha256-dGVzdA=='|https://setting-ignored.unit.invalid")
  assets = UnitAssetSettings.new(root, cdn, use_s3, s3, s3_asset)
  themes = [
    {object_src: ["/objects", "https://objects.unit.invalid", "//protocol-relative.unit.invalid"]},
    {"frame-ancestors" => ["https://extra.unit.invalid", "bad source", "bad\u00a0source", "https://semi.unit.invalid;unsafe"]},
    {script_src: ["'self'", "'unsafe-inline'", "https://ignored.unit.invalid", "/ignored", "'sha256-YWJj'", "'nonce-unit-extension'", "'unsafe-eval'", "'unsafe-eval'", "'bad source'"]},
    {worker_src: ["blob:", "'self'", "'unsafe-inline'", "'nonce-worker'", "'bad;source'"]},
    {style_src: ["https://known-no-op.unit.invalid"]},
  ]
  plugins = [{base_uri: ["/plugin-base", "https://plugin.unit.invalid"]}, {manifest_src: "/unit-manifest"}]
  context = UnitCspContext.new(settings, assets, ["embedded.unit.invalid", "second.unit.invalid"], themes, plugins, File.join(log_root, "#{name}.log"))
  enforced = unit_build_csp(context, "https://forum.unit.invalid", false)
  report = unit_build_csp(context, "https://forum.unit.invalid", true)
  raise "wrong serialized policy type" unless enforced.is_a?(String) && report.is_a?(String)
  raise "upgrade flag semantics changed" unless enforced.start_with?("upgrade-insecure-requests; ") == https && !report.include?("upgrade-insecure-requests")
  raise "default script policy missing" unless enforced.include?("script-src 'strict-dynamic' 'wasm-unsafe-eval'")
  raise "strict-dynamic source filtering failed" if enforced.include?("ignored.unit.invalid") || enforced.include?("'unsafe-inline'")
  raise "none symbol not removed" if enforced.include?("object-src 'none'")
  raise "relative extension normalization lost" unless enforced.include?("object-src https://forum.unit.invalid/objects https://objects.unit.invalid")
  raise "protocol-relative source normalization changed" unless enforced.include?("https://forum.unit.invalid//protocol-relative.unit.invalid")
  raise "known not-yet-extendable directive was emitted" if enforced.include?("style-src")
  raise "duplicate valid source ordering changed" unless enforced.include?("'unsafe-eval' 'unsafe-eval'")
  raise "extension validation allowed whitespace/semicolon" if enforced.include?("bad source") || enforced.include?("bad;source") || enforced.include?("semi.unit.invalid")
  expected_host_reads = restrict && !embed_any ? 2 : 0
  raise "default frame host acquisition omitted/broadened" unless context.host_store.reads == expected_host_reads
  raise "default frame host values changed" if expected_host_reads > 0 && !enforced.include?("https://embedded.unit.invalid https://second.unit.invalid")
  raise "source orchestration order/callbacks changed" unless context.extensions.calls == ["theme:unit-theme", "plugin", "theme:unit-theme", "plugin"] && settings.script_reads == 2
  if !PortableCspUnitProfile.blank?(report_uri)
    expected_tail = "manifest-src 'self' https://forum.unit.invalid/unit-manifest; report-uri #{report_uri}"
    # When Default omits frame-ancestors, Builder appends it AFTER report-uri.
    expected_tail += "; frame-ancestors https://extra.unit.invalid" if expected_host_reads == 0
    raise "default report behavior changed" unless enforced.include?("'report-sample'") && enforced.end_with?(expected_tail)
  else
    raise "blank report URI emitted" if enforced.include?("report-uri") || enforced.include?("'report-sample'")
  end
  worker_cdn = use_s3 && !PortableCspUnitProfile.blank?(s3) ? (PortableCspUnitProfile.presence(s3_asset) || s3) : cdn
  if worker_cdn
    expected_worker = use_s3 ? "#{worker_cdn}/assets/" : "#{worker_cdn}#{root}/assets/"
    raise "default worker CDN source changed" unless enforced.include?(expected_worker)
  end
  warnings = context.warnings
  raise "real warning effects missing" unless warnings.lines.length == 10 && warnings.lines.all? { |line| line.start_with?("WARN: ") } && warnings.include?("Skipping invalid Content Security Policy frame_ancestors") && warnings.include?("Skipping invalid Content Security Policy script_src") && warnings.include?("Skipping invalid Content Security Policy worker_src")
  default_directives = unit_default_directives(context, false)
  raise "default symbol source types changed" unless default_directives[:base_uri] == [:self] && default_directives[:object_src] == [:none] && default_directives[:worker_src].first == :self
  raise "default upgrade source type changed" unless !https || default_directives[:upgrade_insecure_requests] == []
  typed_defaults = default_directives.map do |key, values|
    raise "unsupported default directive type" unless key.is_a?(Symbol) && values.is_a?(Array)
    [key.to_s, values.map { |value| [value.is_a?(Symbol) ? "Symbol" : "String", value.to_s] }]
  end
  puts JSON.generate({typed_default_directives: typed_defaults, name: name, enforced: enforced, report_only: report, warnings: warnings, host_fixture_reads: context.host_store.reads, extension_calls: context.extensions.calls})
  context.close
end
# Unsupported profiles are explicitly rejected before mutation; source-defined
# known no-op directives above are NOT mislabeled as unsupported.
[[], {unknown_directive: "x"}, {script_src: 7}, {script_src: [:self]}, {object_src: ["ok", 7]}].each do |extension|
  begin
    PortableCspUnitProfile.validate_extension!(extension)
    raise "unsupported extension admitted"
  rescue ArgumentError => error
    raise unless error.message.start_with?("unsupported")
  end
end
[nil, 7, :unit].each do |base_url|
  begin
    PortableCspUnitProfile.validate_build!(base_url, false)
    raise "unsupported base URL admitted"
  rescue ArgumentError => error
    raise unless error.message.start_with?("unsupported")
  end
end
begin
  UnitCspSettings.new(1, nil, false, false, "")
  raise "unsupported boolean setting admitted"
rescue ArgumentError => error
  raise unless error.message.start_with?("unsupported")
end
begin
  UnitCspHostStore.new(["unit.invalid", 7])
  raise "unsupported host fixture admitted"
rescue ArgumentError => error
  raise unless error.message.start_with?("unsupported")
end
# Invalid DEFAULT report URI is not an extension warning/drop. The actual Rails
# serializer must raise its specific InvalidDirectiveError, not emit bad headers.
settings = UnitCspSettings.new(false, "https://reports.unit.invalid/bad uri", false, false, "")
context = UnitCspContext.new(settings, UnitAssetSettings.new(nil, nil, false, nil, nil), [], [], [], File.join(log_root, "invalid-default.log"))
begin
  unit_build_csp(context, "https://forum.unit.invalid", false)
  raise "invalid default directive admitted"
rescue ActionDispatch::ContentSecurityPolicy::InvalidDirectiveError => error
  raise "wrong directive error message" unless error.message.start_with?("Invalid Content Security Policy report-uri:")
  raise "default rejection was silently logged/dropped" unless context.warnings.empty?
end
context.close
# Exercise genuine serializer DSL semantics too, not just Builder's current subset.
policy = ActionDispatch::ContentSecurityPolicy.new
unit_set_source(policy, "upgrade-insecure-requests", [])
unit_set_source(policy, "script-src", [:self, :strict_dynamic, :wasm_unsafe_eval, "sha256-YWJj", "sha384-YWJj", "sha512-YWJj"])
unit_set_source(policy, "object-src", [:none])
unit_set_source(policy, "object-src", [])
unit_set_source(policy, "report-uri", ["sha256-unquoted-report-uri"])
serialized = policy.build
raise "serializer source mapping/deletion/report semantics changed" unless serialized == "upgrade-insecure-requests; script-src 'self' 'strict-dynamic' 'wasm-unsafe-eval' 'sha256-YWJj' 'sha384-YWJj' 'sha512-YWJj'; report-uri sha256-unquoted-report-uri"
all_mappings = [:self, :unsafe_eval, :wasm_unsafe_eval, :unsafe_hashes, :unsafe_inline, :none, :http, :https,
  :data, :mediastream, :allow_duplicates, :blob, :filesystem, :report_sample, :script, :strict_dynamic, :ws, :wss]
all_policy = ActionDispatch::ContentSecurityPolicy.new
unit_set_source(all_policy, "worker-src", all_mappings)
all_mapped = all_policy.build
copy = policy.dup
unit_set_source(copy, "script-src", [])
unit_set_source(copy, "report-uri", [:self])
raise "serializer copy/URI symbol changed" unless copy.build == "upgrade-insecure-requests; report-uri self" && policy.build == serialized
["bad source", "bad;source", "bad\nsource", "bad\u00a0source"].each do |source|
  unit_set_source(copy, "report-uri", [source])
  begin
    copy.build
    raise "serializer invalid source admitted"
  rescue ActionDispatch::ContentSecurityPolicy::InvalidDirectiveError => error
    raise "serializer wrong validation message" unless error.message.start_with?("Invalid Content Security Policy report-uri:")
  end
end
puts JSON.generate({serializer_dsl: serialized, all_source_mappings: all_mapped, copy_isolation: true, invalid_sources_refused: 4})
puts "PASS real Default/Builder/ActionDispatch CSP ordering/types/filtering/normalization/warnings/profile refusal"
