# read_nonblock / write_nonblock on a poly-carried IO. Two ways a handle
# becomes poly, and both were broken:
#
#   - Socket.pair answers a poly array, so destructured locals are poly. The
#     poly-as-IO family had no arm for either name, so the call had no emitter
#     at all and the build stopped (#4237).
#   - a user class owning the name opens the per-class poly dispatch instead,
#     and that switch had no arm for the builtin IO tag, so a real Socket
#     raised NoMethodError (#4236).
#
# `exception: false` answers the wait symbol rather than raising, so that
# shape is poly and a String slot cannot hold it.
require "socket"

class FakeTlsSocket
  def read_nonblock(maxlen, exception: true)
    "user-class #{maxlen}"
  end
end

r, w = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)

# nothing written yet: the no-exception shape answers the wait symbol
p r.read_nonblock(4096, exception: false)

# the raising shape reads what is there
w.write("hello")
p r.read_nonblock(4096)

# through a Hash, with the user class in the program: the per-class dispatch
h = { "sock" => w }
s = h["sock"]
p s.read_nonblock(4096, exception: false)

# the user class still answers its own method
p FakeTlsSocket.new.read_nonblock(10)

# write_nonblock through a poly local, including an embedded NUL
n = w.write_nonblock("a\0b")
p n
p r.read_nonblock(3).bytesize

r.close
w.close
puts "ok"
