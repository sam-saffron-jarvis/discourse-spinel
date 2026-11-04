# An inherited ivar widened in the subclass only by the analysis' late ivar
# re-run (after the poly fallback) was not carried back to the base: @items
# settled as sp_PolyArray * in Base and sp_RbVal in Child. Base's methods run
# on a Child through a (sp_Base *) cast, so Base#initialize wrote @w / @h at
# the wrong offsets and Child#area read nil. Ui is never instantiated; its
# `app.attach(self)` is what widens @items.
class Base
  def initialize
    @items = []
    @w = 640
    @h = 480
  end
  def attach(x)
    @items << x
  end
  def size_text
    "#{@w}x#{@h}"
  end
end
class Ui
  def initialize(app)
    app.attach(self)
  end
end
class Child < Base
  def area
    @w * @h
  end
end
c = Child.new
puts c.size_text
puts c.area
