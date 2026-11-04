# A splat into a method called on a value of more than one class spreads
# across each class's own parameters: its fixed ones, its optionals, its rest
# and the parameters after the rest, with the count judged against that
# class's arity. The dispatch used to hand the whole array to the first
# parameter, and every such call stopped the C build.

# The badline shape: a method result splatted behind respond_to?.
class Disk
  def header_block = [18, 0]
  def read_block(track, sector) = [track, sector, 7]
end
class Folder
  def read_block(track, sector) = nil
end
class Drive
  def initialize(storage) = @storage = storage
  def bam
    block = @storage.respond_to?(:header_block) && @storage.read_block(*@storage.header_block)
    block ? block.length : 0
  end
end
p Drive.new(Disk.new).bam
p Drive.new(Folder.new).bam

# Each parameter shape, and the count each one refuses.
class A
  def two(x, y) = [:A, x, y]
  def opt(x, y = 5) = [:A, x, y]
  def rest(x, *r) = [:A, x, r]
  def post(x, *r, z) = [:A, x, r, z]
  def optpost(x, y = 7, *r, z) = [:A, x, y, r, z]
  def kw(x, k: 3) = [:A, x, k]
end
class B
  def two(x, y) = [:B, x, y]
  def opt(x, y = 6, w = 8) = [:B, x, y, w]
  def rest(*r) = [:B, r]
  def post(*r, z) = [:B, r, z]
  def optpost(x, *r) = [:B, x, r]
  def kw(x, y = 1, k: 4) = [:B, x, y, k]
end
class Caller
  def initialize(o) = @o = o
  def try(name, args)
    r = case name
        when :two then @o.two(*args)
        when :opt then @o.opt(*args)
        when :rest then @o.rest(*args)
        when :post then @o.post(*args)
        when :optpost then @o.optpost(*args)
        else @o.kw(*args)
        end
    p r
  rescue ArgumentError => e
    puts "ArgumentError: #{e.message}"
  end
  def lead(args)
    p @o.rest(1, 2, *args)
    p @o.opt(1, *args)
  rescue ArgumentError => e
    puts "ArgumentError: #{e.message}"
  end
  def stmt(args)
    @o.rest(*args)
    :done
  end
end
[A.new, B.new].each do |o|
  c = Caller.new(o)
  [[], [1], [1, 2], [1, 2, 3], [1, 2, 3, 4]].each do |args|
    %i[two opt rest post optpost kw].each { |n| c.try(n, args) }
    c.lead(args)
  end
  p c.stmt([1])
end

# Required parameters after optionals, with and without a rest: CRuby funds
# the required ones first, from the end, and an optional only takes what the
# count leaves over.
class OptTailA
  def f(a = 1, b) = [:A, a, b]
  def g(a = 1, *r, b) = [:A, a, r, b]
  def h(a = 1, c = 2, b) = [:A, a, c, b]
  def k(x, a = 1, c = 2, b, d) = [:A, x, a, c, b, d]
end
class OptTailB
  def f(a = 3, b) = [:B, a, b]
  def g(a = 3, *r, b) = [:B, a, r, b]
  def h(a = 3, c = 4, b) = [:B, a, c, b]
  def k(x, a = 3, c = 4, b, d) = [:B, x, a, c, b, d]
end
class OptTail
  def initialize(o) = @o = o
  def run(args)
    %i[f g h k].each do |n|
      r = case n
          when :f then @o.f(*args)
          when :g then @o.g(*args)
          when :h then @o.h(*args)
          else @o.k(*args)
          end
      p r
    rescue ArgumentError => e
      puts "#{n}: #{e.message}"
    end
  end
  def lead(args)
    p @o.k(0, *args)
  rescue ArgumentError => e
    puts "k: #{e.message}"
  end
end
[OptTailA.new, OptTailB.new].each do |o|
  t = OptTail.new(o)
  [[], [9], [9, 8], [9, 8, 7], [9, 8, 7, 6], [9, 8, 7, 6, 5], [9, 8, 7, 6, 5, 4]].each do |args|
    t.run(args)
    t.lead(args)
  end
end

# Operands: nil, a scalar, nested arrays, a boxed maybe-array, strings,
# objects, and a block passed beside the splat.
class Pt
  attr_reader :v
  def initialize(v) = @v = v
end
class C1
  def m(x = :none, y = :none) = [:C1, x, y]
  def s(a, b) = "#{a}-#{b}"
  def o(pt) = pt.v * 2
  def blk(x, y) = yield(x + y)
  def pblk(x, &b) = b.call(x)
end
class C2
  def m(*r) = [:C2, r]
  def s(a, b) = "#{b}+#{a}"
  def o(pt) = pt.v * 3
  def blk(x, y) = yield(x * y)
  def pblk(x, &b) = b.call(-x)
end
class Operands
  def initialize(o) = @o = o
  def run(flag)
    p @o.m(*nil)
    p @o.m(*5)
    p @o.m(*[[1, 2], [3]])
    h = flag ? [1, 2] : nil
    p @o.m(*h)
    strs = %w[x y]
    p @o.s(*strs)
    pts = [Pt.new(7)]
    p @o.o(*pts)
    p @o.blk(*[3, 4]) { |v| v + 100 }
    p @o.pblk(*[9]) { |v| v * 10 }
  end
end
Operands.new(C1.new).run(true)
Operands.new(C2.new).run(false)

# A reopened Integer as one of the classes, and a default reading an
# earlier parameter.
class Integer
  def span(a, b) = self + a * b
end
class Spanner
  def span(a, b = a * 10) = [:S, a, b]
end
class Spans
  def initialize(o) = @o = o
  def run
    one = [2]
    two = [2, 3]
    p @o.span(*two)
    p @o.span(*one)
  rescue ArgumentError => e
    puts "ArgumentError: #{e.message}"
  end
end
Spans.new(Spanner.new).run
Spans.new(4).run

# The array and the rest built from it survive collections in between.
class G1
  def m(x, *r) = [x.to_s, r.map(&:to_s)]
end
class G2
  def m(x, y = "d", *r) = [x.to_s * 2, y.to_s, r.size]
end
class Churn
  def initialize(o) = @o = o
  def mk(i) = (0..i).map { |k| "s#{k}" * 3 }
  def run
    acc = 0
    300.times do |i|
      v = @o.m(*mk(i % 20))
      acc += v[0].size + v[1].size
    end
    acc
  end
end
p Churn.new(G1.new).run
p Churn.new(G2.new).run
