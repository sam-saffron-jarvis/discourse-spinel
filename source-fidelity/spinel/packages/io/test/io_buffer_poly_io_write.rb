# A poly-carried IO handle keeps its #write/#puts/#flush arms in a program
# that also uses IO::Buffer. The buffer's implicit splice registers a native
# class, and the poly-IO dispatch used to disable itself whenever ANY native
# class existed -- `fds[1].write(...)` answered NoMethodError naming IO.
class Sentinel
  def initialize(tag)
    @tag = tag
  end
end
fds = { 0 => $stdin, 1 => $stdout, 2 => Sentinel.new("dir") }
b = IO::Buffer.new(16)
b.set_string("Hello, poly IO!\n")
io = fds[1]
n = io.write(b.get_string(0, 16))
p n
io.flush
io = fds[2]
p io.is_a?(Sentinel)
