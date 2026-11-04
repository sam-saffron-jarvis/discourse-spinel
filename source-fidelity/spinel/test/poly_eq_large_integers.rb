# Two integers read out of poly slots compare as INTEGERS. The numeric
# fallback converts both to double, which above 2^53 is lossy: two numbers
# 62 apart landed on the same double and compared equal. The fallback is
# there for the mixed int/float case and keeps it.
class Box
  def initialize(v)
    @v = v
  end

  def eq(o) = @v == o
  def eql(o) = @v.eql?(o)
  def cmp(o) = @v <=> o
end

p Box.new(-3145750702635002333).eq(-3145750702635002395)
p Box.new(100000000000000001).eq(100000000000000002)
p Box.new(4611686018427387903).eq(4611686018427387902)
p Box.new(4611686018427387903).eq(4611686018427387903)

# the mixed case the fallback exists for
p Box.new(1).eq(1.0)
p Box.new(1.0).eq(1)
p Box.new(1).eql(1.0)
p Box.new(1).eql(1)

# ordering was already exact; keep it pinned beside the equality
p Box.new(100000000000000001).cmp(100000000000000002)
p Box.new(100000000000000002).cmp(100000000000000001)

# and the containers that key on the same comparison
p({ 100000000000000001 => "a" }[100000000000000002])
p({ 100000000000000001 => "a" }[100000000000000001])
p [100000000000000001].include?(100000000000000002)
p [100000000000000001, 100000000000000002].uniq.size
