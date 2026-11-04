# Every operation on a closed handle raises IOError. The write side and the
# position queries used to answer a seed, so a write to a closed socket
# looked like a successful send of zero bytes.
r, w = IO.pipe
w.write("hello\n")
w.close
r.close

def try
  yield.inspect
rescue IOError => e
  "IOError: #{e.message}"
end

puts try { w.write("x") }
puts try { w.puts("x") }
puts try { w.print("x") }
puts try { w.flush }
puts try { w.fileno }
puts try { w.tell }
puts try { r.read }
puts try { r.gets }
puts try { r.eof? }
p w.closed?
p r.closed?
p w.close
