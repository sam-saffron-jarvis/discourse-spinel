# A call on an object receiver binds a rest-parameter method the way a call by
# name does: the parameters after the rest take the call's last arguments, a
# splat spreads across the ones ahead of it, and a count below what the target
# requires is CRuby's ArgumentError -- where the body ran with the missing
# parameters padded out.

def bad
  yield
  puts "no error"
rescue ArgumentError => e
  puts "#{e.class}: #{e.message}"
end

class Talker
  def one(a, *rest) = [a, rest]
  def two(a, b, *rest) = [a, b, rest]
  def opt(a, b = 2, *rest) = [a, b, rest]
  def post(*rest, z) = [rest, z]
  def mid(a, *rest, z) = [a, rest, z]
  def own = one           # implicit self, the same lowering
  def blk(a, *rest, &b) = [a, rest, b ? b.call : nil]
  def two_post(a, *rest, y, z) = [a, rest, y, z]
  def optpost(a, b = 1, *rest, z) = [a, b, rest, z]
  def kwr(a, *rest, **opts) = [a, rest, opts]
  def kwd(a, *rest, k: churn(1)) = [a, rest, k.length]
  def nk(a, b, k: 9) = [a, b, k]
end

class Echo < Talker
  def one(a, *rest) = super
end

# An override that takes a smaller count answers for itself: the arm the
# receiver selects judges the count, not the laxest one in the hierarchy.
class Strict
  def count(a, *rest) = a + rest.length
end

class Loose < Strict
  def count(a = 0, *rest) = a + rest.length + 100
end

# A subclass that takes a smaller count keeps the call for the whole hierarchy.
class Soft
  def one(a, *rest) = [:soft, a, rest]
end

class Softer < Soft
  def one(a = 0, *rest) = [:softer, a, rest]
end

class Louder < Talker
  def one(a, *rest) = [:loud, a, rest]
end

Point = Struct.new(:x) do
  def scale(f, *more) = [x * f, more]
end

def top(a, *rest) = [a, rest]

module Greeter
  def greet(name, *rest) = [name, rest]
end

class Host
  include Greeter
end

def side
  puts "side"
  1
end

def churn(n)
  a = []
  120.times { |i| a << i + n }
  a
end

t = Talker.new

# counts the target takes
p t.one(1)
p t.one(1, 2, 3)
p t.two(1, 2)
p t.opt(1)
p t.opt(1, 5, 6)
p t.post(1, 2, 3)
p t.mid(1, 2, 3, 4)
p Louder.new.one(1, 2)
p Host.new.greet("hi")
p Softer.new.one
p Loose.new.count
p Strict.new.count(5)
p Echo.new.one(1, 2)
p t.blk(1, 2) { 7 }
p t.blk(1)
p t.send(:one, 1, 2)
p t.two_post(1, 2, 3, 4, 5)
p t.two_post(1, 2, 3)
p Point.new(3).scale(2, 9)
p t.optpost(1, 2)
p t.optpost(1, 2, 3, 4)
p t.kwr(1, 2, k: 3)
p t.nk(*[1, 2], k: 7)
p t.nk(*[1, 2])

# a splat spreads across the fixed parameters, its tail fills the rest
args = [1, 2, 3]
p t.one(*args)
p t.one(*[7])
p t.mid(1, *[2, 3], 9)
p t.two(*args)
p top(*[1, 2])
h = { k: [1, 2, 3] }
p t.one(*h[:k])
poly = [1, "a", :b]
p t.one(*poly)

# the packed rest stays live while the arguments after it are evaluated
live = 0
40.times do
  a, r, z = t.mid(1, *[2, 3], churn(7))
  live += 1 if a == 1 && r == [2, 3] && z.length == 120
  r2, z2 = t.post(churn(8))
  live += 1 if r2 == [] && z2.length == 120
  b, r3, n = t.kwd(1, *[2, 3])
  live += 1 if b == 1 && r3 == [2, 3] && n == 120
end
p live

# a shortfall is refused, not padded
bad { t.one }
bad { t.two(1) }
bad { t.opt }
bad { t.post }
bad { t.mid }
bad { t.own }
bad { Louder.new.one }
bad { Strict.new.count }
bad { Host.new.greet }
bad { t.one { 1 } }
bad { t.one(*[]) }
bad { t.two(*[1]) }
bad { t.send(:one) }
bad { t.two_post(1, 2) }
bad { Echo.new.one }
bad { Point.new(3).scale }
empty = [1, 2].select { |v| v > 9 }
bad { top(*empty) }

# the arguments are evaluated before the count is refused
bad { t.two(side) }
