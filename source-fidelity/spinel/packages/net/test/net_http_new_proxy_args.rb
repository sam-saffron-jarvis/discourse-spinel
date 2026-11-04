# Net::HTTP.new with CRuby's positional proxy arguments, and ssl_timeout.
#
# `Net::HTTP.new(host, port, nil)` is how a program asks for a DIRECT
# connection -- a Rails app pinning a resolved address against DNS rebinding
# writes it so an egress proxy cannot re-resolve the host. It used to be an
# ArgumentError here (given 3, expected 1..2), at runtime.
#
# No network: nothing below connects.
require "net/http"

http = Net::HTTP.new("example.com", 443, nil)
p [http.address, http.port]

# The splat of an empty proxy list, the other spelling of "no proxy".
proxy_options = []
http = Net::HTTP.new("example.com", 443, *proxy_options)
p http.port

http.ipaddr = "93.184.215.14"
http.use_ssl = true
p http.ssl_timeout
http.ssl_timeout = 5
p http.ssl_timeout

# A NAMED proxy is refused rather than connected straight past. (CRuby
# accepts it and connects through the proxy; this client has none.)
begin
  Net::HTTP.new("example.com", 443, "proxy.internal", 3128)
  puts "WRONG: accepted a proxy"
rescue NotImplementedError => e
  puts e.message
end
