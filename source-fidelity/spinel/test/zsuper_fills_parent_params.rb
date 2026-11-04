# A bare `super` from a method with fewer parameters than its parent fills
# the parent's extra optional, rest, keyword and ** slots with their
# defaults; the C call was an argument short (#4852).

class Base1
  def initialize(x, **)
    @x = x
  end
  def x = @x
  def run(x, **) = x * 2
end
class Grey1 < Base1
  def initialize(x)
    @grey = x == 1
    super
  end
  def run(x) = super
end
p Grey1.new(5).x
p Grey1.new(5).run(3)
class Base2
  def initialize(x, **kw)
    @x = x
  end
  def x = @x
  def run(x, **kw) = x * 2
end
class Grey2 < Base2
  def initialize(x)
    @grey = x == 1
    super
  end
  def run(x) = super
end
p Grey2.new(5).x
p Grey2.new(5).run(3)
class Base3
  def initialize(x, jumper: false)
    @x = x
  end
  def x = @x
  def run(x, jumper: false) = x * 2
end
class Grey3 < Base3
  def initialize(x)
    @grey = x == 1
    super
  end
  def run(x) = super
end
p Grey3.new(5).x
p Grey3.new(5).run(3)
class Base4
  def initialize(x, *)
    @x = x
  end
  def x = @x
  def run(x, *) = x * 2
end
class Grey4 < Base4
  def initialize(x)
    @grey = x == 1
    super
  end
  def run(x) = super
end
p Grey4.new(5).x
p Grey4.new(5).run(3)
class Base5
  def initialize(x, y = 2)
    @x = x
  end
  def x = @x
  def run(x, y = 2) = x * 2
end
class Grey5 < Base5
  def initialize(x)
    @grey = x == 1
    super
  end
  def run(x) = super
end
p Grey5.new(5).x
p Grey5.new(5).run(3)
class Base6
  def initialize(x, *rest, k: 1, **kw)
    @x = x
  end
  def x = @x
  def run(x, *rest, k: 1, **kw) = x * 2
end
class Grey6 < Base6
  def initialize(x)
    @grey = x == 1
    super
  end
  def run(x) = super
end
p Grey6.new(5).x
p Grey6.new(5).run(3)
