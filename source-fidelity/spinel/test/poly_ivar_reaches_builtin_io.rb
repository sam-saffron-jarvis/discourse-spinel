# A user class's method name shared with IO: the poly dispatch switches on the
# user classes' cls_id, so a real stream in the same slot has to reach the
# builtin arm rather than the NoMethodError default (#4341).
require "socket"

class Sink
  def close; "sink closed"; end
  def closed?; false; end
end

class Wrapper
  def initialize(io)
    @io = io
  end

  def close
    @io.close
  end

  def closed?
    @io.closed?
  end
end

a, b = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
w = Wrapper.new(b)
p w.closed?
p w.close
p w.closed?

s = Wrapper.new(Sink.new)
p s.close
p s.closed?

r, wr = IO.pipe
pw = Wrapper.new(wr)
p pw.closed?
pw.close
p pw.closed?
a.close
r.close
