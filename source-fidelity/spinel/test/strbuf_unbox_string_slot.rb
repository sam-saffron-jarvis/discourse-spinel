# A mutable String (a builder, promoted by its appends) boxed into a poly slot
# and unboxed into a String slot: the slot must hold the string's bytes, not
# the builder's handle.
# On 129f3323 the first two lines print the handle's bytes in place of each
# mutable string (different bytes each run) and the last three print 200,
# plain and under SPINEL_GC_STRESS=1 (three runs each). CRuby prints what
# the .expected holds.

# narrowed by is_a?(String) inside a recursive walk
class Walk
  def self.walk(node, &block)
    return block.call(node) if node.is_a?(String)
    node.each { |child| walk(child, &block) }
  end
  def self.go(root)
    out = []
    walk(root) { |n| out << n }
    out.join(",")
  end
end
s = +"a"
s << "bc"
puts Walk.go([[s], "b"])
t = +"q"
3.times { |i| t << "r#{i}" }
puts Walk.go([t, [t]])

# narrowed by is_a?(String), then concatenated after an allocating call
def churn
  a = []
  60.times { |i| a << "c#{i}" << ("m#{i}".dup << "x") }
  a.size
end
def mk(k)
  u = +"q"
  3.times { |i| u << "r#{i}" }
  [u, k]
end
w = 0
200.times do |k|
  v = mk(k)[0]
  if v.is_a?(String)
    x = v + churn.to_s
    w += 1 unless x == "qr0r1r2120"
  end
end
p w

# bound by a rightward hash pattern into a local that already holds a String
def mkh(k)
  u = +"q"
  3.times { |i| u << "r#{i}" }
  { name: u, n: k }
end
w = 0
200.times do |k|
  name = "init"
  mkh(k) => { name: }
  w += 1 unless name + churn.to_s == "qr0r1r2120"
end
p w

# bound by a nested multiple assignment into a local that already holds a String
w = 0
200.times do |k|
  nm = "init"
  x = [1, mk(k)]
  a, (nm, n) = x
  w += 1 unless nm + churn.to_s == "qr0r1r2120"
end
p w
