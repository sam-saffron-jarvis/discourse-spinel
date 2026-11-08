# frozen_string_literal: true
require "json"
require "digest"
root = ARGV.fetch(0)
extra_root = ARGV.fetch(1)
roots = ["#{root}/frontend/discourse/dist/assets", "#{root}/frontend/discourse/scripts", extra_root]
manifest = JSON.parse(File.read("#{root}/frontend/discourse/dist/manifest/manifest.json"))
names = manifest.fetch("entrypoints").values.map { |name| name.delete_prefix("assets/").delete_suffix(".js") }
# Actual source assets exercise non-pre-digested SHA1 + supplied version too.
names += ["js/browser-detect", "js/browser-update"]
asset_reads = names.map do |name|
  file = roots.map { |path| File.join(path, "#{name}.js") }.find { |path| File.file?(path) }
  raise "genuine requested asset absent" unless file
  content = File.binread(file)
  [name, content.bytesize, Digest::SHA256.hexdigest(content)]
end
puts JSON.generate({genuine_asset_reads: asset_reads})
settings_cases = [
  ["plain", nil, nil, false, nil, nil, nil],
  ["root", "/unit-root", nil, false, nil, nil, nil],
  ["cdn", "/unit-root", "https://cdn.unit.invalid", false, nil, nil, nil],
  ["s3", "/unit-root", nil, true, "https://s3.unit.invalid", nil, "gzip"],
  ["s3-no-encoding", "/unit-root", nil, true, "https://s3.unit.invalid", nil, nil],
  ["s3-asset-cdn", "/changed-root", "https://cdn.unit.invalid", true, "https://s3.unit.invalid", "https://assets.unit.invalid", "gzip, br"],
  ["s3-fallback-empty", nil, "//cdn.unit.invalid", true, "https://s3.unit.invalid", "", "br"],
  ["s3-off-no-url", nil, nil, true, nil, nil, "br"],
  ["escaped-unit-root", "/unit&\"<root", "https://cdn.unit.invalid", false, nil, nil, "gzip"],
]
settings_cases.each do |label, relative_root, cdn, use_s3, s3_cdn, s3_asset_cdn, encoding|
  settings = UnitAssetSettings.new(relative_root, cdn, use_s3, s3_cdn, s3_asset_cdn)
  helper = new_unit_url_helper(settings, roots, "2-unit-A", encoding)
  paths = names.map { |name| helper.script_asset_path(name) }
  raise "wrong URL type" unless paths.all? { |path| path.is_a?(String) }
  if label == "s3-asset-cdn"
    raise "wrong original S3/root/brotli URL" unless paths.first.start_with?("https://assets.unit.invalid/assets/br/") && !paths.first.include?("changed-root")
  elsif label == "root"
    raise "root omitted" unless paths.first.start_with?("/unit-root/assets/")
  end
  # Real missing asset refusal, never a manufactured /assets/name URL.
  begin
    helper.script_asset_path("js/unit-definitely-missing")
    raise "missing asset admitted"
  rescue StandardError => error
    raise unless missing_asset_error?(error)
    raise "missing asset error type/message changed" unless error.class.name == "Propshaft::MissingAssetError" && error.message == "The asset 'js/unit-definitely-missing.js' was not found in the load path."
  end
  puts JSON.generate({label: label, paths: paths})
end
# Same genuine plain asset + changed version changes digest; already digested
# files retain original digested filename regardless of configured version.
settings = UnitAssetSettings.new(nil, nil, false, nil, nil)
a = new_unit_url_helper(settings, roots, "2-unit-A", nil)
b = new_unit_url_helper(settings, roots, "2-unit-B", nil)
first = a.script_asset_path("js/browser-detect")
second = b.script_asset_path("js/browser-detect")
raise "digest version ignored" if first == second
source_bytes = File.binread("#{root}/frontend/discourse/scripts/js/browser-detect.js")
expected_digest = Digest::SHA1.hexdigest("#{source_bytes}2-unit-A")[0, 8]
raise "wrong source-content digest" unless first == "/assets/js/browser-detect-#{expected_digest}.js"
raise "predigested path redigested" unless a.script_asset_path(names.first) == b.script_asset_path(names.first)
# Tail handling is Rails asset_path's actual string handling, not URL escaping.
query = b.asset_paths.asset_path("js/browser-update.js?unit=1&x=2#fragment")
raise "asset tail lost" unless query.end_with?("?unit=1&x=2#fragment")
puts JSON.generate({version_a: first, version_b: second, query: query})
# Unit path fixture uses genuine source bytes under deliberately unusual names
# and overlapping roots. It tests original resolution semantics, not production.
fixture_names = ["unit space&quote'雪.js", "unit-special-abcdefgh.digested.js", "unit-precedence.js"]
helper = new_unit_url_helper(settings, [extra_root, "#{extra_root}/nested"], "2-unit-A", nil)
fixture_urls = fixture_names.map { |name| helper.asset_cdn_path(name) }
raise "path characters were silently rewritten" unless fixture_urls.first.include?("unit space&quote'雪-")
raise "predigested fixture ignored" unless fixture_urls[1].end_with?("unit-special-abcdefgh.digested.js")
puts JSON.generate({fixture_urls: fixture_urls})
reversed_nested = new_unit_url_helper(settings, ["#{extra_root}/nested", extra_root], "2-unit-A", nil)
raise "nested root dedup changed" unless reversed_nested.asset_cdn_path("unit-precedence.js") == fixture_urls.last
priority_a = ARGV.fetch(2)
priority_b = ARGV.fetch(3)
priority_first = new_unit_url_helper(settings, [priority_a, priority_b], "2-unit-A", nil).asset_cdn_path("unit-precedence.js")
priority_second = new_unit_url_helper(settings, [priority_b, priority_a], "2-unit-A", nil).asset_cdn_path("unit-precedence.js")
raise "root priority ignored" if priority_first == priority_second
priority_a_digest = Digest::SHA1.hexdigest("#{File.binread(File.join(priority_a, 'unit-precedence.js'))}2-unit-A")[0, 8]
raise "wrong file-root priority" unless priority_first == "/assets/unit-precedence-#{priority_a_digest}.js"
puts JSON.generate({first_root: priority_first, changed_first_root: priority_second})
puts "PASS genuine file-backed Propshaft/digest/URL/root/CDN/S3/missing/type/tail unit controls"
