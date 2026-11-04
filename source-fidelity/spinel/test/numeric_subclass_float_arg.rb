# A Numeric of the program's own converts through its #to_f where a Float
# argument is taken (Math.sqrt, Math.log), as CRuby's rb_to_float does; a
# user object that is not a Numeric is still "can't convert X into Float".
class Money < Numeric
  def initialize(c) = @c = c
  def to_f = @c / 100.0
end
class Plain
  def to_f = 4.0
end

m = Money.new(1600)
p Math.sqrt(m)
p Math.log(Money.new(100))
xs = [Money.new(400), 9]
p Math.sqrt(xs[0])
p Math.sqrt(xs[1])
begin
  Math.sqrt([Plain.new, 1][0])
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
