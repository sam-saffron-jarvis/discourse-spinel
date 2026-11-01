require_relative "../lib/surface"

def check(value, name)
  raise name unless value
  puts name
end

File.write("build/assets/native-boundary.js", "/* native test */\x00")
File.write("build/assets/native-boundary.txt", "not public")
File.write("build/tmp/native-boundary-secret.js", "not public")
File.symlink("../tmp/native-boundary-secret.js", "build/assets/native-boundary-link.js")
begin
  paths = NativePaths.new("/node/jarvis/widgets/discourse-spinel-app")
  check(paths.route("/node/jarvis/widgets/discourse-spinel-app/latest") == "/latest" && paths.route("/latest") == "/latest", "prefixed and proxy-stripped native routes")
  check(paths.route("/node/jarvis/widgets/discourse-spinel-app-extra/latest") != "/latest", "prefix boundary is segment exact")
  check(paths.local_url("/latest") == "/node/jarvis/widgets/discourse-spinel-app/latest", "outbound mount prefix")
  asset = paths.asset("/assets/native-boundary.js")
  check(asset && asset[0] == "text/javascript; charset=utf-8" && asset[1] == "/* native test */\x00", "static MIME and binary length")
  bad = %w[/assets/../compile.json /assets/%2e%2e/compile.json /assets/foo%2fbar.js /assets//native-boundary.js /assets/.hidden.js /assets/native-boundary.txt /assets/native-boundary-link.js /data/emoji-unicode.json /assets/native-boundary.js.map /assets/native-boundary.js.gz]
  check(bad.all? { |path| paths.asset(path).nil? }, "traversal symlinks source maps evidence and unknown MIME fail closed")
  rejected = 0
  ["/", "//evil", "/ok/../bad", "/ok/", "/a?b", "/a\"b", "https://evil", "/a%2fb"].each do |prefix|
    begin
      NativePaths.new(prefix)
    rescue
      rejected += 1
    end
  end
  check(rejected == 8 && NativePaths.new("").local_url("/latest") == "/latest", "mount config rejects ambiguous and injectable paths")
ensure
  %w[build/assets/native-boundary.js build/assets/native-boundary.txt build/assets/native-boundary-link.js build/tmp/native-boundary-secret.js].each { |path| File.delete(path) }
end
