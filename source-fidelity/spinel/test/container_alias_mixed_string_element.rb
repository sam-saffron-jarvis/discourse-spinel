# The heterogeneity gate that keeps a user method reachable through an untyped
# slot (#4240) must not cost the container's OWN strings their handles. `box`
# holds a Frag and a mutable String: refusing the container wholesale left the
# String element a plain frozen box, so `s.replace` answered the receiver and
# the array never saw the mutation. Demand the stores into handles first, then
# decline to narrow the LOCAL -- the Frag keeps its own #replace, and the
# String element still mutates in place.
class Frag
  def initialize(html)
    @html = html
  end

  def replace(selector)
    "user-replace:" + selector + ":" + @html
  end
end

box = [Frag.new("abc"), +"just a string"]

f = box[0]
puts f.replace("sel")

s = box[1]
s.replace("swapped")
puts s
puts box[1]

# the append shape reaches the same alias binding
n = box[1]
n << "!"
puts box[1]
