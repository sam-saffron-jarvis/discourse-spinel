# The SP_BUILTIN_IO arms of the poly dispatch, exercised together: a user
# class owning #write/#flush opens the per-class switch, and a Socket
# carrying the builtin IO tag must reach its own arms (#4226, #4227). The
# non-String write arm boxes a scalar temp and checks the tag at run time,
# so an Integer argument stringifies and a poly-carried String with an
# embedded NUL keeps its full width (740a6bc9).

require "socket"

class UnrelatedUser
  def write(_data) = 0
  def flush = 0
end

r, w = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
n = w.write("hello")
raise "wrote=#{n}" unless n == 5
w.flush
puts "ok flush"

# an Integer argument through the non-String arm: CRuby writes its to_s
n = w.write(12345)
raise "int wrote=#{n}" unless n == 5

# a String that reaches the arm only as a runtime poly value, with an
# embedded NUL: the tag check routes it byte-length-sized
def opaque(s)
  [s, 7].sample && s
end
v = opaque("a\0b")
n = w.write(v)
raise "nul wrote=#{n}" unless n == 3
w.flush

got = r.read(13)
p got.bytesize
p got == "hello12345a\0b"
puts "ok"
