# A Thread (or Fiber) body nested in another needs the enclosing object's
# self: an ivar, a method call on it, self itself. The outer body's capture
# walk stopped at a nested block, since a block's locals are its own, and
# took that to mean its self was too: the outer fiber captured nothing and
# the inner one's capture was filled from a `self` the outer never had (a C
# error naming an identifier the source never wrote). The walk goes through
# nested blocks for self now, as the proc capture walk always has (#4620,
# ryudoawaru).
class Box
  def initialize; @seen = []; @n = 2; end
  def add(x) = @seen << x
  def run
    Thread.new { Thread.new { @seen << :x }.join }.join
    Thread.new { Thread.new { add(:y) }.join }.join
    Thread.new { Thread.new { Thread.new { @seen << self.class.to_s }.join }.join }.join
    f = Fiber.new { Fiber.new { @seen << :f }.resume }
    f.resume
    Thread.new { [1, 2].each { |i| @seen << i * @n } }.join
    Thread.new { t = Thread.new { 5 }; @seen << t.value }.join
    @seen
  end
end
p Box.new.run
