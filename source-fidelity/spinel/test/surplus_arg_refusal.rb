# A call CRuby refuses with ArgumentError is refused here too, on the direct
# and the instance-dispatch path alike: a surplus positional into a callee
# whose only other parameter is a keyword or a `**kw` (keyword parameters are
# no positional slot), and a keyword hash no parameter names when the callee
# declares keywords (it is keywords then, not the options hash).
def t
  yield
rescue ArgumentError => e
  e.message
end

class Rest
  def m(x, *rest) = [x, rest.size]
  def run = [m(3), m(3, 4), m(1, k: 9), m(2, "s" * 2)]
end
p Rest.new.run

class Kw
  def m(x, k: 1) = [x, k]
  def run = t { m(3, 4) }
end
p Kw.new.run
p t { Kw.new.m(3, 4) }
p Kw.new.m(3, k: 5)
def kwf(x, k: 1) = [x, k]
p t { kwf(3, 4) }
p kwf(3)

class B
  def m(x, **kw) = [x, kw.size]
end
def f(x, **kw) = [x, kw.size]
p t { B.new.m(3, 4) }
p t { f(3, 4) }
p t { f }
p f(3, a: 1, b: 2)
p B.new.m(3, a: 1)

def g2(x, y = 7, k: 1) = [x, y, k]
p t { g2(1, j: 2) }
p g2(1, 2, k: 3)
p t { Kw.new.m(1, j: 2) }

def req_kw(x, k:) = [x, k]
p t { req_kw(1) }
p req_kw(1, k: 2)

# a callee without keywords still takes a braceless hash positionally
def opts(x, o = {}) = [x, o]
p opts(1, j: 2)
