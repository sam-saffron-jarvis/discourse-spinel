# IO#write on a poly receiver: a Socket or File that reaches a per-class
# poly dispatch through any user class defining #write must dispatch the
# builtin tag to sp_File_write (which internally routes to sp_sock_write
# when the receiver is a socket). Without the SP_BUILTIN_IO arm in the
# dispatch, the call raises "undefined method 'write' for an instance
# of Socket" in AOT (CRuby inherits IO#write on Socket via BasicSocket,
# so the same code is silent there).

require "socket"

class StubSslSocket
  def write(_data); 42; end
end

# Pair the per-class dispatch with a user class that owns #write, so the
# codegen opens the poly switch instead of the static-method fast path.
# The plain Socket below carries the builtin IO tag and reaches the new
# SP_BUILTIN_IO arm.
r, w = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
n = w.write("hello")
raise "wrote=#{n}" unless n == 5
puts "ok"
