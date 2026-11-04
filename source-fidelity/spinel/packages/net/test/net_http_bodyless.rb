# A HEAD answer, a 204 and a 304 have no body whatever their headers say:
# the client read one anyway and waited until the server closed the
# connection, which a keep-alive server does not (#5044). The server here
# keeps every connection open until the client is done.
require "net/http"

server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]
held = []
answers = [
  "HTTP/1.1 204 No Content\r\nConnection: keep-alive\r\n\r\n",
  "HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: keep-alive\r\n\r\n",
  "HTTP/1.1 304 Not Modified\r\nContent-Length: 5\r\nConnection: keep-alive\r\n\r\n",
]
t = Thread.new do
  answers.each do |a|
    c = server.accept
    while (line = c.gets)
      break if line.strip.empty?
    end
    c.write(a)
    held << c
  end
end

started = Time.now
r = Net::HTTP.new("127.0.0.1", port).get("/nothing")
puts "#{r.code} #{r.body.inspect}"
r = Net::HTTP.new("127.0.0.1", port).head("/page")
puts "#{r.code} #{r.body.inspect}"
r = Net::HTTP.new("127.0.0.1", port).get("/cached")
puts "#{r.code} #{r.body.inspect}"
puts(Time.now - started < 2 ? "without waiting" : "waited for the server")
t.join
held.each(&:close)
