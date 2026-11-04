# `a, b = Socket.pair(...)` types both targets as IO handles, the way
# `r, w = IO.pipe` already did. The general multiple-assignment path reads a
# USER method's multi-value return; a builtin class method has no scope to
# read, so the few that answer a fixed pair are named beside IO.pipe.
#
# Without it both targets settled poly, and every method gated on a typed
# receiver could not reach them: recv_nonblock is gated on TY_IO, so it
# answered NoMethodError on a perfectly good socket.
require "socket"

a, b = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
p a.class                       # the RUNTIME kind answers #class, not the slot
b.write "x"
p a.recv_nonblock(64)

c, d = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
p c.recv_nonblock(64, exception: false)

e, f = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
f.send("hi", 0)
p e.recv(8)

g, h = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
h.write "z"
p g.read(1)
p IO.select([g], nil, nil, 1).nil?
p g.fileno > 0
g.close
p g.closed?

# through a method that answers the pair
def mk
  Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
end
i, j = mk
j.write "m"
p i.read_nonblock(1)

# IO.pipe, which had this already, is unchanged
r, w = IO.pipe
w.write "y"
p r.read_nonblock(1)
p r.class

# Typing the targets routes write to the TYPED arm, which chose the binary
# entry by the operand's STATIC type -- so an operand whose class is only
# known at run time took the plain entry and an embedded NUL truncated the
# write. It picks by the tag now, as the poly-receiver arm always did.
def opaque(s)
  [s, 7].sample && s
end
k, l = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
p l.write(opaque("a\0b"))
p k.read(3).bytesize
m, n = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
p n.write(opaque("c\0d"), opaque("e\0f"))
p m.read(6).bytesize
o, q = IO.pipe
p q.write(opaque("x\0y"))
p o.read(3).bytesize
