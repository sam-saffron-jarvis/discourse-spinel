# Instance-variable targets of a multiple assignment outside any class: the
# top level (the Toplevel pseudo-class global) and a class body (the
# module-level slot), from a literal, a typed array a call answers, a boxed
# array, a builtin's pair, and a scalar. The single write always knew these
# homes; the multiple assignment wrote `self->iv_x` into main (no self) for
# a literal, dropped the store for an array value, and skipped an ivar
# target under a scalar value in any scope.
@x, @y = [1, 2]
p @x, @y
def two = [3, 4]
@a, @b = two
p @a, @b
def poly(v) = v
poly("s")
@c, @d = poly([5, 6])
p @c, @d
@lo, @hi = [1, 2, 3, 4].partition { |n| n < 3 }
p @lo, @hi
@m, @n = 13
p @m, @n
class K
  @p, @q = [14, 15]
  def self.pq = [@p, @q]
  def initialize
    @r, @s = [16, 17]
  end
  def rs = [@r, @s]
end
p K.pq
p K.new.rs
