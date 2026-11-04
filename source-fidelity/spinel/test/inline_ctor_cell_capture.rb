# A yielding `initialize` is INLINED at its `.new` site, and the inliner
# declares the body's locals under renamed names (`total` -> `_y<tag>_total`),
# a celled one as `_cell__y<tag>_total`. A capture taken inside that body has
# to name the cell the same way; naming it `_cell_total` emits a reference to
# an identifier that was never declared, and the C compiler rejects the
# program. Both capture sites are covered: the proc capture struct, and
# Fiber.new's.

class Counter
  def initialize
    total = 0
    @bump = proc { total += 1 }
    @read = proc { total }
    yield self
  end

  def bump
    @bump.call
  end

  def read
    @read.call
  end
end

counter = Counter.new { |c| c }
counter.bump
counter.bump
puts counter.read

class Pump
  def initialize
    total = 0
    @fib = Fiber.new do
      3.times { total += 1; Fiber.yield total }
      total
    end
    yield self
  end

  def step
    @fib.resume
  end
end

pump = Pump.new { |p| p }
pump.step
pump.step
puts pump.step
