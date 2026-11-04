# A String mutated in place and then stored in a container is boxed as its
# shared-mutable handle. A poly dispatch built for a name a user class also
# defines had no arm for the handle and raised NoMethodError on a String
# (#5048); it now reads the live string. A mutator keeps the handle, so the
# stored element changes with it.
class Box
  def empty? = true
  def size = 0
  def upcase = "BOX"
  def <<(o) = self
end

s = +"ab"
s << "c"
[s, Box.new].each { |x| p x.empty? }
[s, Box.new].each { |x| p x.size }
[s, Box.new].each { |x| p x.upcase }
[s, Box.new].each { |x| x << "!" }
p s
e = +""
e << ""
[e, Box.new].each { |x| p x.empty? }
