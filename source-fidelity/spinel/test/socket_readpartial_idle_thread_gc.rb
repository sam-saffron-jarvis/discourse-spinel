# A green thread blocked in IO#readpartial on a socket whose peer never sends
# went into a plain read(2) on its OS worker without parking. The worker never
# reached a safepoint, so the first stop-the-world collection waited for it
# forever: every other thread froze at its next allocation, and a server with
# one idle client did not answer anyone (#4528, ryudoawaru). Every read entry
# point parks on readiness first; readpartial, getc, getbyte, readbyte and
# eof? did not.
require 'socket'

def idle_reader(sock)
  Thread.new do
    buf = +''
    loop { sock.readpartial(8192, buf) }
  rescue StandardError
    nil
  end
end

server = TCPServer.new('127.0.0.1', 0)
idle_server = TCPServer.new('127.0.0.1', 0)

idle_client = TCPSocket.new('127.0.0.1', idle_server.addr[1])
idle_side = idle_server.accept
writer = TCPSocket.new('127.0.0.1', server.addr[1])
reader = server.accept

t = idle_reader(idle_side)
sleep 0.1

# getc / getbyte / readbyte / eof? on quiet pipes, the same shape
r0, w0 = IO.pipe
r1, w1 = IO.pipe
r2, w2 = IO.pipe
r3, w3 = IO.pipe
t2 = Thread.new { r0.getc }
t3 = Thread.new { r1.getbyte }
t4 = Thread.new { r2.eof? }
t5 = Thread.new { r3.readbyte rescue :eof }
sleep 0.1

# Collect on every round while the readers sit idle: each collection stops
# the world, which needs every worker at a safepoint.
rounds = 0
buf = +''
30.times do
  writer.write('x' * 64)
  reader.readpartial(8192, buf)
  rounds += 1 if buf.size == 64
  garbage = Array.new(200) { |i| "s#{i}" * 4 }
  GC.start
end
puts "rounds=#{rounds}"
p t.alive?

# The idle peers hang up: each reader wakes with EOF and ends.
idle_client.close
[w0, w1, w2, w3].each(&:close)
p t.join(5).nil?
p t2.join(5)&.value
p t3.join(5)&.value
p t4.join(5)&.value
p t5.join(5)&.value
