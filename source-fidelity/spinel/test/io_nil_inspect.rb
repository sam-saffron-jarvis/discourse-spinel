# A NULL handle IS nil -- the readiness family answers one on timeout -- but it
# inspected as a closed IO, so a `puts v.inspect` read as `#<IO:(closed)>`
# where CRuby says `nil`. nil? and truthiness were already right, which is why
# it only misread (#4316).
r, w = IO.pipe
io = IO.for_fd(r.fileno, autoclose: false)
v = io.wait_readable(0.01)
puts v.inspect
puts v.nil?
puts(v ? "truthy" : "falsy")
p v

w.write("x")
v2 = io.wait_readable(0.5)
puts v2.nil?
puts v2.inspect.start_with?("#<IO:fd ")
p r.read(1)

# a handle that is genuinely CLOSED is a different thing and keeps its own
r2, w2 = IO.pipe
r2.close
puts r2.inspect
w2.close

File.write("io_nil_inspect_tmp.txt", "x")
f = File.open("io_nil_inspect_tmp.txt", "r")
puts f.inspect.start_with?("#<File:")
f.close
puts f.inspect.end_with?("(closed)>")
File.delete("io_nil_inspect_tmp.txt")
