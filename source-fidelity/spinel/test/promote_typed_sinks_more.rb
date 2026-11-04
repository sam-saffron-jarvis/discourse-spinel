# Three more typed sinks fed from a boxed value -- what every int local and
# every call answer is under --int-overflow=promote -- that convert at the
# sink, as the typed sinks of the same family already do: the value of a
# Struct member store through a variable key (boxed at the site, sp_int in
# the store), the start and length of a boxed Array's slice!, and the typed
# Hash / Array elements of a multiple assignment whose right-hand sides are
# boxed. Both modes; the default mode's C for each is unchanged.
S = Struct.new(:a, :b)
s = S.new(1, 2)
i = 1
v = (s[i] = 7)
p v
p s.b
w = (s[:a] = v + 1)
p w
p s.a

def cut(x, i, n) = x.slice!(i, n)
a = [1, 2, 3, 4, 5]
p cut(a, i, 2)
p a
def gcv(i) = i * 2

h = { "a" => 1 }
60.times { |k| h["k#{k}"], h["m#{k}"] = k, gcv(k) }
p h.size, h["k59"], h["m59"]
ia = [0, 0, 0]
fa = [0.0, 0.0]
5.times { |k| ia[k % 3], fa[k % 2] = gcv(k), gcv(k) / 4.0 }
p ia, fa

# a user-defined != whose parameter widened to poly, called with an
# unboxed literal: the site handed the raw int where the general call path
# boxes it (in the default mode too, once a String reaches the parameter)
class N3
  def initialize(b) = @b = b
  def !=(o) = @b != o
end
x = N3.new(3)
p(x != 3)
p(x != "s")
p(x != 4)
p(N3.new(3) != 3)
