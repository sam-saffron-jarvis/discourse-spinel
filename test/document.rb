require "json"
require "uri"
require_relative "../frontend/native_document"

def check(value, name)
  raise name unless value
  puts name
end

prefix = "/node/jarvis/widgets/discourse-spinel-app"
unsafe = "</ScRiPt><img src=x onerror=alert(1)> & <!-- <script>"
preloads = { "topic_list" => JSON.generate({ "topics" => [{ "title" => unsafe }] }) }
doc = NativeDocument.new(prefix)
html = doc.render(preloads, { "default_locale" => "en", "title" => unsafe, "smtp_password" => "must-not-appear" }, "https://hub.samsaffron.com")
check(html.include?('<section id="main">') && !html.include?("<table"), "source document mounts Ember without a bespoke table")
check(!html.include?("must-not-appear") && html.include?("<title>Latest topics - &lt;/ScRiPt&gt;"), "document title escaped and unrelated settings never dumped")
raw = html[/<script type="application\/json" id="data-preloaded">(.*?)<\/script>/m, 1].to_s
check(!raw.include?("<") && !raw.include?(">") && !raw.include?("&"), "script JSON neutralizes HTML parser metacharacters")
unpacked = JSON.parse(raw)
check(JSON.parse(unpacked["topic_list"])["topics"][0]["title"] == unsafe, "hostile script preload round trips without changing data")
encoded = html[/name="discourse\/config\/environment" content="([^"]+)"/, 1].to_s
config = JSON.parse(URI.decode_www_form_component(encoded))
check(config["rootURL"] == prefix && config["environment"] == "production" && html.include?('class="text-size-normal anon"'), "source environment metadata and anonymous layout classes")
imports = JSON.parse(html[/<script type="importmap">(.*?)<\/script>/m, 1].to_s)["imports"]
check(!imports.empty? && imports.all? { |key, value| key.start_with?("#{prefix}/assets/") && value.start_with?("#{prefix}/assets/") }, "relative module imports resolve through prefixed stable URL map")
worker = doc.render_service_worker("https://hub.samsaffron.com")
check(worker.include?("self.addEventListener('push'") && worker.include?("#{prefix}/share-target") && !worker.include?("__MINIMAL_BASE_"), "actual core service worker receives native mount and origin")
rejected = false
begin
  doc.render({ "site" => "invalid JSON" }, {}, "http://127.0.0.1:3498")
rescue JSON::ParserError
  rejected = true
end
check(rejected, "invalid preload JSON fails closed")
