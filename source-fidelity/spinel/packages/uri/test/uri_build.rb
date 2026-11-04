# URI::HTTP(S).build from keyword components, diffed against CRuby: the
# scheme comes from the class, userinfo rides before the host, a nil port
# is left off #to_s, and the result reads back through the same readers a
# parsed URI answers.
require "uri"
u = URI::HTTPS.build(userinfo: "id:secret", host: "api.github.com", path: "/applications/id/grant")
p u.to_s
p [u.scheme, u.userinfo, u.host, u.path]
p u.request_uri
h = URI::HTTP.build(host: "example.com", path: "/a", query: "q=1")
p h.to_s
p URI::HTTPS.build(host: "example.com", port: 8443, path: "/").to_s
p URI::HTTPS.build(host: "example.com").to_s
