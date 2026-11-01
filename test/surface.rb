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
  prefix = paths.base_uri
  cooked = '<p><img src="/images/emoji/twitter/wave.png?v=16"><a href="/latest">local</a><a href="https://example.com">external</a><img src="//cdn.example/a.png"><a data-href="/not-a-link" href="#anchor">anchor</a></p>'
  mounted = cooked.sub('src="/images/', "src=\"#{prefix}/images/").sub('href="/latest"', "href=\"#{prefix}/latest\"")
  check(paths.mount_cooked(cooked) == mounted && paths.mount_cooked(mounted) == mounted, "mounted cooked response rebases local URLs once without changing external protocol-relative or fragment URLs")
  check(NativePaths.new("").mount_cooked(cooked) == cooked, "root cooked response preserves source bytes without rebaking")
  payload = JSON.generate({ "post_stream" => { "posts" => [{ "id" => 7, "cooked" => cooked }] } })
  check(JSON.parse(paths.mount_topic(payload))["post_stream"]["posts"][0] == { "id" => 7, "cooked" => mounted }, "mount adapter preserves native post identity and changes only cooked local URL attributes")
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
