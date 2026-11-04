# A block passed through a forwarding method into a Ruby-defined Enumerable
# method (`def cnt(&) = @items.count(&)`) resolved a bare call in its body
# against the INTERMEDIATE receiver's class: the yield fallback carried one
# level of self, so the block spliced two inlines deep ran as the
# forwarding object, and `big?` (defined on the caller) folded to
# NoMethodError. The fallback now carries the self of the block one level
# out as well, and moves it down when the splice moves that block in.
class Reg
  def initialize; @items = [1, 2, 3]; end
  def cnt(&) = @items.count(&)
  def fnd(&) = @items.find(&)
  def each(&) = @items.each(&)
end
class App
  def initialize; @seen = []; end
  def big?(i) = i > 1
  def run
    r = Reg.new
    p r.cnt { |i| big?(i) }
    p r.fnd { |i| big?(i) }
    r.each { |i| @seen << i if big?(i) }
    p @seen
  end
end
App.new.run
class Outer
  def initialize; @r = Reg.new; @tag = "o"; end
  def label(i) = "#{@tag}#{i}"
  def via(&) = @r.cnt(&)
  def go
    p via { |i| label(i) == "o2" }
    p @r.fnd { |i| label(i) == "o3" }
    p @r.cnt { |i| @tag == "o" && i > 1 }
  end
end
Outer.new.go
