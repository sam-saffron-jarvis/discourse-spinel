# A dispatch switch arm fills its method's omitted defaults on the receiver,
# seen as the arm's class: `def m(x, y = @extra)` in a subclass reads the
# receiver's @extra, and `y = self` is the receiver. The arm read them
# against the caller's self -- the base class, which has no such field, or
# at top level no self at all -- so the switch did not compile. An argument
# the caller passes is still the caller's expression (#4873).

class A
  def initialize
    @k = 1
  end

  def m(x, y = @k) = [x, y]
  def run = m(1)
  def run_arg = m(@k + 10)
end

class B < A
  def initialize
    super
    @extra = 7
  end

  def m(x, y = @extra, z = x + @extra) = [x, y, z]
end

class S < A
  def m(x, y = self) = [x, y.class]
end

class Meth < A
  def extra = 5
  def m(x, y = extra) = x + y
end

class Same < A
  def initialize
    super
    @extra = 9
  end

  def m(x, y = @extra) = [x, y]
end

class Caller
  def initialize
    @extra = 100
    @k = 200
  end

  def go(o) = o.m(2)
end

p [A.new.run, A.new.run_arg, A.new.m(3), A.new.m(4, 5)]
p [B.new.run, B.new.run_arg, B.new.m(3), B.new.m(3, 4)]
p [S.new.run, S.new.run_arg, S.new.m(3)]
p [Meth.new.run, Meth.new.m(3)]
p [Same.new.run, Same.new.m(3)]
p Caller.new.go(A.new)

class Plain
  def initialize
    @extra = 7
  end

  def m(x, y = @extra) = x + y
end

p Plain.new.m(1)

class Base2
  def initialize
    @extra = 3
  end
end

class NoOverride < Base2
  def m(x, y = @extra) = x + y
end

p NoOverride.new.m(1)

# A String default the method retains in an ivar and appends to is a shared
# handle, filled on the receiver too.
class SA
  def initialize
    @k = +"a"
  end

  def m(x, s = @k)
    @buf = s
    @buf << "!"
    [x, @buf]
  end

  def run = m(1)
end

class SB < SA
  def initialize
    super
    @extra = +"b"
  end

  def m(x, s = @extra)
    @buf = s
    @buf << "?"
    [x, @buf]
  end
end

p [SA.new.run, SB.new.run, SB.new.m(2), SB.new.m(3, +"c")]

# A call nested in the arm's own argument -- a splatted array, a string built
# from it -- fills its defaults on its own receiver, not the arm's.
class NA
  def initialize
    @k = 1
  end

  def m(x, y = @k) = "#{x}/#{y}"
  def run_splat(o) = m(*[o.m(10)])
  def run_str(o) = m(o.m("a") + "!")
end

class NB < NA
  def initialize
    super
    @extra = 7
  end

  def set(e)
    @extra = e
    self
  end

  def m(x, y = @extra) = "#{x}/#{y}"
end

o = NB.new.set(99)
p [NB.new.run_splat(o), NB.new.run_str(o), NA.new.run_splat(o), NA.new.run_str(o)]
