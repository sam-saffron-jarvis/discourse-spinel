# `private attr_writer :x` (and reader / accessor) declares the method and
# makes it private: self.x = v works inside the class, an outside call
# raises NoMethodError (#4922).
class C
  private attr_writer :x
  def set(v)
    self.x = v
    @x
  end
end
p C.new.set(5)
begin
  C.new.x = 1
  puts "no error"
rescue NoMethodError => e
  puts "NoMethodError"
end
class D
  private attr_reader :r
  private attr_accessor :a
  protected attr_writer :w
  def initialize = (@r = 1; self.a = 2; self.w = 3)
  def both = [r, a, @w]
end
p D.new.both
begin
  D.new.a
rescue NoMethodError
  puts "NoMethodError"
end
