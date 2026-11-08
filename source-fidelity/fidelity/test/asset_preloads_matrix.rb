# frozen_string_literal: true
# Isolated dependency matrix; context is loaded explicitly by the driver.
root = ARGV.fetch(0)
manifest = JSON.parse(File.read("#{root}/frontend/discourse/dist/manifest/manifest.json"))
chunks = PortableEmberAssetGraph.script_chunks(manifest)
EmberAssets.script_chunks = chunks
urls = {}
asset_proof = []
chunks.values.flatten.uniq.each do |name|
  data = File.binread("#{root}/frontend/discourse/dist/assets/#{name}.js")
  urls[name] = "https://assets.unit.invalid/assets/#{name}.js"
  asset_proof << [name, data.bytesize, Digest::SHA256.hexdigest(data)]
end
# Supplied unknown-entry fallback is an explicit unit input, NOT a real asset.
urls["unit-fallback"] = "https://assets.unit.invalid/fallback.js"
helper = UnitAssetHelper.new(chunks, urls, "unit-nonce-A")
raise "preload state eagerly allocated" unless helper.asset_preload_links.nil?
rows = []
rows << fragment_record(helper.preload_script("discourse", type_module: true,
  attrs: {"data-<&\"'" => "value-<&\"'\n雪", "async" => ""}))
rows << fragment_record(helper.module_preloads_for("discourse", nil, "discourse", "unknown-entry"))
rows << fragment_record(helper.preload_script("unit-fallback"))
rows << fragment_record(helper.preload_script_url("/unit-direct.js", attrs: {}, type_module: false))
rows << fragment_record(helper.preload_script_url("/unit-direct.js", attrs: nil, type_module: true))
expected_links = [urls.fetch(chunks.fetch("discourse").first), urls.fetch("unit-fallback"), "/unit-direct.js", "/unit-direct.js"].map do |url|
  "<#{url}>; rel=\"preload\"; as=\"script\""
end
raise "resource ordering/duplicates/module side effects changed" unless helper.asset_preload_links == expected_links
raise "attribute escaping absent" unless rows.first.fetch(:text).include?("data-&lt;&amp;&quot;&#39;=\"value-&lt;&amp;&quot;&#39;\n雪\"")
raise "module choice changed" unless rows.first.fetch(:text).include?('type="module"')
raise "defer choice changed" unless rows[2].fetch(:text).include?("<script defer ")
raise "wrong nonce" unless rows.all? { |row| row.fetch(:text).include?('nonce="unit-nonce-A"') }
module_text = rows[1].fetch(:text)
expected_module_urls = chunks.fetch("discourse").map { |name| urls.fetch(name) }
raise "module preload count changed" unless module_text.scan('<link rel="modulepreload"').length == expected_module_urls.length
raise "module ordering changed" unless expected_module_urls.each_cons(2).all? { |a, b| module_text.index(a) < module_text.index(b) }
puts JSON.generate({rows: rows, links: helper.asset_preload_links, genuine_assets: asset_proof})
# Changed context MUST affect both output and isolated collector, never a frozen
# first oracle nonce/URL or shared controller list. Nonce is a supplied unit value.
changed_urls = urls.transform_values { |url| url.sub("assets.unit.invalid", "changed.unit.invalid") }
changed = UnitAssetHelper.new(chunks, changed_urls, "unit-nonce-B")
changed_row = fragment_record(changed.preload_script("discourse", attrs: {"data-live" => "changed & value"}))
raise "captured nonce" unless changed_row.fetch(:text).include?('nonce="unit-nonce-B"')
raise "captured URL" unless changed_row.fetch(:text).include?("changed.unit.invalid")
raise "controller state leaked" unless changed.asset_preload_links.length == 1 && helper.asset_preload_links == expected_links
puts JSON.generate({changed: changed_row, links: changed.asset_preload_links})
missing = UnitAssetHelper.new(chunks, {}, "unit-nonce-missing")
begin
  missing.preload_script("discourse")
  raise "missing asset URL accepted"
rescue KeyError
  raise "missing asset caused collector effects" unless missing.asset_preload_links.nil?
end
# Duplicate resource preloads are deliberately retained by the original; an
# incorrect Set collector must be rejected, unlike module-preload deduplication.
raise "wrong output accepted" if rows.first.fetch(:text).sub("unit-nonce-A", "wrong") == rows.first.fetch(:text)
raise "wrong ordering accepted" if helper.asset_preload_links.reverse == expected_links
puts "PASS isolated source helper escaping/order/nonce/type/collector/missing-URL controls"
