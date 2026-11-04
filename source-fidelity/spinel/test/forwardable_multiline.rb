# def_delegator(s) whose symbol list continues onto following lines, or
# names more than sixteen methods: only the first line's were defined (#4822).

require "forwardable"
class Inner
  def a = 1
  def b = 2
  def c = 3
  def d = 4
  def e = 5
  def f = 10
  def g = 11
  def h = 12
  def i = 13
  def j = 14
  def k = 15
  def l = 16
  def m = 17
  def n = 18
  def o = 19
  def p = 20
  def q = 21
end
class O1
  extend Forwardable
  def_delegators :@inner, :a,
                 :b
  def initialize = @inner = Inner.new
end
class O2
  extend Forwardable
  def_delegators :@inner, :a, :b,
                 :c, :d, :e
  def initialize = @inner = Inner.new
end
class O3
  extend Forwardable
  def_delegators(:@inner, :a,
                 :b)
  def initialize = @inner = Inner.new
end
class O4
  extend Forwardable
  def_delegator :@inner, :a,
                :z
  def initialize = @inner = Inner.new
end
class O5
  extend Forwardable
  def_delegators :@inner,
                 :a, :b
  def initialize = @inner = Inner.new
end
class O6
  extend Forwardable
  def_delegators :@inner, :a, \
                 :b
  def initialize = @inner = Inner.new
end
class O7
  extend Forwardable
  def_delegators :@inner, :a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l, :m, :n, :o, :p, :q
  def initialize = @inner = Inner.new
end
p [O1.new.a, O1.new.b]
p [O2.new.c, O2.new.e]
p [O3.new.a, O3.new.b]
p O4.new.z
p [O5.new.a, O5.new.b]
p [O6.new.a, O6.new.b]
p [O7.new.a, O7.new.q]
p __LINE__
