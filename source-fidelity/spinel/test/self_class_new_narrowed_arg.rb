# `self.class.new(x.to_i, y.to_i)` in a leaf class passed its arguments raw,
# and an sp_int narrowed by to_i into a poly initialize parameter did not
# compile. The arguments are converted to the parameter types, as `V.new(...)`
# does (#4534, elektronaut).
class V
  attr_reader :x, :y
  def initialize(x, y)
    @x = x
    @y = y
  end
  def to_i_vector
    self.class.new(x.to_i, y.to_i)
  end
  def to_f_vector
    self.class.new(x.to_f, y.to_f)
  end
  def scaled(k = 2)
    self.class.new(x * k, y * k)
  end
  def swapped = self.class.new(y, x)
end
v = V.new(2.4, 3.6)
p v.to_i_vector.x, v.to_i_vector.y
p V.new(2, 3).to_i_vector.x
p V.new(2, 3).to_f_vector.y
p v.scaled.x, v.scaled(3).y
p v.swapped.x
class P
  attr_reader :n
  def initialize(n = 0) = @n = n
  def succ = self.class.new(n + 1)
end
p P.new(1).succ.n, P.new.succ.n
