# The String index-assignment forms reach the ivar through its reader, as
# `<<` already did: the reader hands out the shared handle and the write
# lands on the ivar's own string.

class C
  def initialize = @name = +"abc"
  def name = @name
end
c = C.new
c.name[0] = "X"
c.name << "!"
p c.name

class W
  attr_reader :s
  def initialize = @s = +"abcdef"
end
w = W.new
w.s[1, 2] = "YY"
w.s["d"] = "D"
w.s[4..4] = "E"
w.s.insert(0, ">")
p w.s
v = (w.s[0] = "<")
t = w.s.insert(1, "-")
p v, t, w.s

class P
  attr_reader :label
  def initialize = @label = +"one"
end
class Q
  attr_reader :label
  def initialize = @label = +"two"
end
[P.new, Q.new].each { |o| o.label[0] = "T"; p o.label }
