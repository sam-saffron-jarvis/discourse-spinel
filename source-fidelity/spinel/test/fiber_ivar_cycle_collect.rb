# An object holding a suspended Fiber in an ivar whose block captures the
# object (#4525): every fiber on the fiber list was a collector root, so the
# cycle survived every collection and the owner (and its 512 KB table) was
# never reclaimed. Only the running fiber and the resumers waiting on it are
# roots now; a suspended fiber lives by reference and marks its saved stack
# when it is scanned. GC.stat["bytes"] is absent under CRuby, so the test
# prints true there too.
class Node
  def initialize
    @big  = Array.new(65_536, 0)
    @loop = Fiber.new { loop { tick } }
  end
  def tick = Fiber.yield
  def go = @loop.resume
end

200.times { Node.new.go }
GC.start
p((GC.stat["bytes"] || 0) < 20_000_000)

# the variants that were flat already stay flat, and a fiber reached only
# through its owner still runs when the owner lives
class Keeper
  def initialize = @f = Fiber.new { |x| loop { x = Fiber.yield(x * 2) } }
  def step(v) = @f.resume(v)
end
k = Keeper.new
GC.start
p k.step(2)
GC.start
p k.step(5)
h = 0
200.times { |i| f = Fiber.new { Fiber.yield i; i + 1 }; f.resume; h += 1 }
GC.start
p h
