# A `method(:m)` capture anywhere in the program pinned m's poly return to
# Integer for EVERY caller, the direct ones included: `ip = obj.ip` on a
# `String | nil` method read the String's to_i (142 for "142.250.185.206")
# once `obj.method(:ip)` appeared (#4451). The pin predates the bind site's
# return-kind stamp; the capture is called correctly through that now, and the
# return is left as the body says.
class Sub
  def initialize(ok)
    @ok = ok
  end
  def ip
    "142.250.185.206" if @ok
  end
end
ip = Sub.new(true).ip
m = Sub.new(true).method(:ip)
puts "#{ip}"
puts m.call.inspect

# a dispatch-table shape: the captured methods answer an ivar that widens
# only after the capture's parameters are pinned, and the direct caller
# must read the widened return, not the String it was derived as
class Pad
  def initialize = @latch = nil
  def peek(a) = @latch
  def poke(a, v) = @latch = v.odd? ? "s" : v
end
pad = Pad.new
table = [pad.method(:poke), pad.method(:peek)]
table[0][1, 3]
p table[1][1]
table[0].call(1, 4)
p table[1].call(1)
p pad.peek(0)
