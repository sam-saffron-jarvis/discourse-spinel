# A method whose parameter default reads an earlier parameter
# (`def f(x, y = 7, z = x * 2)`) binds a call's keyword hash the way any
# other method does: a key binds by name only to a keyword parameter, and
# a hash no keyword parameter takes is one more positional argument, which
# fills the first unfilled optional. That path looked every key up by
# parameter name and never passed the hash positionally, so `f(1, k: 9)`
# ran with y at its default and `f(2, y: 3)` bound y to 3 (#4869).

def f(x, y = 7, z = x * 2) = [x, y, z]
def f_first(x, y = x + 1) = [x, y]
def f_hash(x, y = {}, z = x * 2) = [x, y, z]
def f_kw(x, y = 7, z = x * 2, k: 1) = [x, y, z, k]
def f_kwonly(a:, b: a * 2) = [a, b]
def f_plain(x, y = 7) = [x, y]

p f(2)
p f(1, k: 9)
p f(1, k: 9, j: 8)
p f(1, "a" => 2)
p f(2, y: 3)
p f(1, 5)
p f(1, 5, 6)
p f_first(1, k: 9)
p f_hash(1, k: 9)
p f_hash(2)
p f_kw(1, k: 3)
p f_kw(1)
p f_kwonly(a: 4)
p f_kwonly(a: 4, b: 1)
p f_plain(1, k: 9)
p((f_plain(1, 5, 6) rescue :argument_error))

class Obj
  def f(x, y = 7, z = x * 2) = [x, y, z]
  def run = [f(1, k: 9), f(2)]
  def self.g(x, y = 7, z = x * 2) = [x, y, z]
end

o = Obj.new
p o.f(1, k: 9)
p o.run
p Obj.g(1, k: 9)
p Obj.g(3)

class Base
  def m(x) = [x]
  def run = m(1, k: 9)
end

class Sub < Base
  def m(x, y = 7, z = x * 2) = [x, y, z]
end

p Sub.new.run
p((Base.new.run rescue :argument_error))
