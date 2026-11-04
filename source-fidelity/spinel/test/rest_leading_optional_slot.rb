def r(a = {}, *rest, c) = [a, rest, c]
p r(5)
p r(1, 5)
p r(1, 2, 3, 5)
def r2(a = 1, b = 2, *rest, c, d) = [a, b, rest, c, d]
p r2(8, 9)
p r2(7, 8, 9)
p r2(6, 7, 8, 9)
p r2(5, 6, 7, 8, 9)
def kk(a = {}, c, **kw) = [a, c, kw]
p kk(5)
p kk(4, 5)
p kk(5, j: 1)
p kk(4, 5, j: 1)
def kr(a = :d, *r, c, k: 0) = [a, r, c, k]
p kr(1)
p kr(1, k: 2)
p kr(1, 2, 3, k: 4)
class O
  def r(a = {}, *rest, c) = [a, rest, c]
  def kk(a = {}, c, **kw) = [a, c, kw]
end
o = O.new
p o.r(5)
p o.r(1, 2, 5)
p o.kk(5)
p o.kk(4, 5, j: 1)
# a keyword after the post-rest parameters binds by name
def kq(*r, c, k: 0) = [r, c, k]
p kq(1, k: 2)
p kq(1, 2)
