# IO#sync= (and #sync) on a poly receiver: a File read back out of a Hash
# carries no static type, and the poly-as-IO family had no sync= arm, so the
# documented "unbuffer me" idiom raised NoMethodError (#4229). The answers
# mirror the typed-receiver arms: sync= flushes on a truthy value and answers
# it, sync reads the handle kind (a file is buffered, a socket is not).
require "socket"

class StubFile
  def write(_) = 0
end

path = "/tmp/spinel_test_sync_poly.#{Process.pid}"
data = { "k" => File.open(path, "w") }
f = data["k"]
f.write("x")
f.sync = true
f.close
File.delete(path)
puts "file ok"

pair = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
s = [pair[0]].sample
s.sync = true
p s.sync

puts "ok"
