# frozen_string_literal: true
require "json"
require "digest"
root = ARGV.fetch(0)
extra = ARGV.fetch(1)
roots = ["#{root}/frontend/discourse/dist/assets", "#{root}/frontend/discourse/scripts", extra]
manifest = JSON.parse(File.read("#{root}/frontend/discourse/dist/manifest/manifest.json"))
digested = manifest.fetch("entrypoints").fetch("discourse").delete_prefix("assets/")
plain = File.binread("#{root}/frontend/discourse/scripts/js/browser-detect.js")
digest = Digest::SHA1.hexdigest("#{plain}2-unit-response")[0, 8]
plain_path = "js/browser-detect-#{digest}.js"
fallback_paths = []
app = lambda do |env|
  fallback_paths << env.fetch("PATH_INFO")
  [418, {"content-type" => "text/plain"}, ["unit fallback"]]
end
server = new_unit_asset_response(app, roots, "2-unit-response")
requests = [
  ["GET", "/assets/#{digested}"], ["HEAD", "/assets/#{digested}"],
  ["GET", "/assets/#{plain_path}"], ["HEAD", "/assets/#{plain_path}"],
  ["GET", "/assets/js/browser-detect-bad00000.js"],
  ["GET", "/assets/js/unit-missing.js"], ["POST", "/assets/#{digested}"],
  ["GET", "/not-assets/#{digested}"],
  ["GET", "/assets/unit+space%26%E9%9B%AA-abcdefgh.digested.js"],
  ["GET", "/assets/%2e%2e/unit-outside.js"],
]
rows = []
requests.each_with_index do |(method, path), index|
  env = {"REQUEST_METHOD" => method, "PATH_INFO" => path}
  env["HTTP_IF_NONE_MATCH"] = "unit deliberately ignored by this original component" if index == 2
  status, headers, body = server.call(env)
  raise "response types changed" unless status.is_a?(Integer) && headers.is_a?(Hash) && body.is_a?(Array) && body.all? { |part| part.is_a?(String) }
  if [0, 1, 2, 3, 8].include?(index)
    raise "genuine file response not 200" unless status == 200
    raise "wrong JS MIME" unless headers["Content-Type"] == "text/javascript"
    raise "immutable cache header lost" unless headers["Cache-Control"] == "public, max-age=31536000, immutable"
    raise "Vary header lost" unless headers["Vary"] == "Accept-Encoding"
    expected = index < 2 ? File.binread("#{roots.first}/#{digested}") : plain
    raise "wrong content length" unless headers["Content-Length"] == expected.bytesize.to_s
    raise "wrong content hash ETag" unless headers["ETag"] == "\"#{Digest::SHA1.hexdigest("#{expected}2-unit-response")[0, 8]}\""
    if method == "HEAD"
      raise "HEAD leaked body" unless body.empty?
    else
      raise "actual compiled JS bytes changed" unless body.join == expected
    end
  elsif index == 6 || index == 7
    raise "fallback omitted" unless status == 418 && body == ["unit fallback"]
  else
    raise "missing/stale asset not 404" unless status == 404 && body == ["Not found"] && headers["Content-Length"] == "9"
  end
  rows << {method: method, path: path, status: status, headers: headers, parts: body.length,
           bytes: body.sum { |part| part.bytesize }, body_sha256: Digest::SHA256.hexdigest(body.join)}
end
raise "fallback effects changed" unless fallback_paths == ["/assets/#{digested}", "/not-assets/#{digested}"]
# Explicit genuine NullFileWatcher unit profile: it clears/seeds under the
# original mutex every call. This is not an ActiveSupport/evented watcher.
refresh_file = File.join(extra, "unit-refresh.js")
version_a = File.binread("#{root}/frontend/discourse/scripts/js/browser-detect.js")
version_b = File.binread("#{root}/frontend/discourse/scripts/js/browser-update.js")
File.binwrite(refresh_file, version_a)
old_hash = Digest::SHA1.hexdigest("#{version_a}2-unit-response")[0, 8]
new_hash = Digest::SHA1.hexdigest("#{version_b}2-unit-response")[0, 8]
refresh_server = new_unit_asset_response(app, [extra], "2-unit-response", true, "null")
cached_server = new_unit_asset_response(app, [extra], "2-unit-response")
old_env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/unit-refresh-#{old_hash}.js"}
raise "cold refresh body changed" unless refresh_server.call(old_env)[2] == [version_a] && cached_server.call(old_env)[2] == [version_a]
# Mutation belongs to this labelled owned UNIT fixture, never source/shared data.
File.binwrite(refresh_file, version_b)
raise "disabled sweeper lost original cache semantics" unless cached_server.call(old_env)[2] == [version_a]
raise "NullFileWatcher did not invalidate stale digest" unless refresh_server.call(old_env)[0] == 404
new_env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/unit-refresh-#{new_hash}.js"}
raise "NullFileWatcher did not reseed real bytes" unless refresh_server.call(new_env)[2] == [version_b]
File.delete(refresh_file)
raise "NullFileWatcher served deleted file" unless refresh_server.call(new_env)[0] == 404
puts JSON.generate({responses: rows, fallback_paths: fallback_paths, null_watcher_refresh_verified: true})
begin
  server.call({"REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/invalid%QQ.js"})
  raise "malformed percent escape accepted"
rescue ArgumentError
end
puts "PASS genuine Propshaft GET/HEAD/digest/404/decode/headers/body/fallback in isolated Rack context; no listener/page"
