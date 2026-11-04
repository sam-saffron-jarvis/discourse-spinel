# A key of another class stored into a hash that arrived through dup or
# clone: the copy has the literal's variant, and the mixed-key widening
# looked only at literals assigned to locals and passed at calls, so a
# Symbol into a dup'ed String-keyed hash raised TypeError and into a dup'ed
# Integer-keyed one landed as INT64_MIN. The widening follows dup / clone and
# a local holding the literal back to the literal (#4540, elektronaut).
h = { "x" => 150 }.dup
h[:x] = 1
p h
h2 = { 1 => 150 }.clone
h2[:x] = 1
p h2
g = { "x" => 150 }
h3 = g.dup
h3[:x] = 1
p h3
p g
def f(h)
  h[:x] = 1
  h
end
p f({ "x" => 150 }.dup)
p f({ x: 0 })
# same-kind stores and reads through a copy were always right
h4 = { "x" => 150 }.dup
h4["y"] = 2
p h4, h4[:x], h4.key?(:x)

# the vector2d shape: parse_hash(arg.dup)
class Vec
  attr_reader :x, :y
  def initialize(x, y) = (@x, @y = x, y)
  def self.parse_hash(hash)
    hash[:x] ||= hash["x"]
    hash[:y] ||= hash["y"]
    new(hash[:x], hash[:y])
  end
  def self.parse(arg) = parse_hash(arg.dup)
end
v = Vec.parse({ "x" => 150, "y" => 100 })
p [v.x, v.y]
