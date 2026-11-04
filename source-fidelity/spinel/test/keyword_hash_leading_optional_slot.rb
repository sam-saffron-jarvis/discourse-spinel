# A keyword hash that no keyword parameter takes is one more positional
# argument, bound the way any argument is: the required parameters are
# funded first, including those after the optionals, then the optionals
# left to right. With a leading optional the hash therefore lands in the
# required parameter behind it, not in the optional: `def h(a = {}, c)`
# called `h(k: 9)` answers `[{}, {k: 9}]`. The slot helper picked the first
# unfilled optional, which gave `a` the hash and `c` nothing, and a
# positional argument before the hash went to `c` instead of `a` (#4877).

def h(a = {}, c) = [a, c]
p h(k: 9)
p h(1, k: 9)
p h(1, 2)
p h("s" => 1)

def g(a = {}, b = {}, c) = [a, b, c]
p g(k: 9)
p g(1, k: 9)
p g(1, 2, k: 9)

def m(a, b = {}, c) = [a, b, c]
p m(1, k: 9)
p m(1, 2, k: 9)

def big(a, b = 2, c = 3, d, e) = [a, b, c, d, e]
p big(1, 4, k: 9)
p big(1, 2, 4, k: 9)
p big(1, 2, 3, 4, k: 9)

def n(a = nil, c) = [a, c]
p n(k: 9)
p n(1, k: 9)

def t(a = {}, c) = [a, c]
p t(1, 2)
p t(k: 9)
p t("x", k: 9)
begin
  t(1, 2, k: 9)
rescue ArgumentError => e
  p e.message
end

# a keyword parameter takes the key; a **kwrest takes the hash
def w(a = {}, c, k: 0) = [a, c, k]
p w(1, k: 9)
def kk(c, a = {}, **kw) = [c, a, kw]
p kk(1, k: 9)

# trailing optionals are unchanged: the hash fills the first one
def tr(a, b = {}) = [a, b]
p tr(1, k: 9)
def u(a = nil, b = nil) = [a, b]
p u(k: 9)

class C
  def h(a = {}, c) = [a, c]
  def self.h(a = {}, c) = [:cls, a, c]
end
o = C.new
p o.h(k: 9)
p o.h(1, k: 9)
p C.h(k: 9)
p C.h(1, k: 9)

class P
  def initialize(a = {}, c)
    @v = [a, c]
  end
  attr_reader :v
end
p P.new(k: 9).v
p P.new(1, k: 9).v

def yh(a = {}, c)
  yield [a, c]
end
yh(k: 9) { |v| p v }
yh(1, k: 9) { |v| p v }

class A
  def tail(c, a = {}) = [:A, c, a]
end
class B
  def tail(c, a = {}) = [:B, c, a]
end
[A.new, B.new].each { |x| p x.tail(1, k: 9) }
