# `100 Continue` before the final response is read past: the client answered
# the 100 and handed the final response over as its body (#5045).
require "net/http"

server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]
t = Thread.new do
  c = server.accept
  while (line = c.gets)
    break if line.strip.empty?
  end
  c.write("HTTP/1.1 100 Continue\r\n\r\n" \
          "HTTP/1.1 103 Early Hints\r\nLink: </a.css>\r\n\r\n" \
          "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nX-Final: yes\r\nConnection: close\r\n\r\nok")
  c.close
end

res = Net::HTTP.new("127.0.0.1", port).post("/", "")
puts "#{res.code} #{res.body.inspect} #{res["x-final"]}"
t.join
