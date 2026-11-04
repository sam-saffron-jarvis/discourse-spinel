# A Range interpolated into a string renders as its to_s; every Range kind
# was refused as an "unsupported interpolation value" (#4824).

r = 2..5
puts "#{r}"
puts "#{2...5}"
puts "#{(2..)}"
puts "#{1.5..2.5}"
puts "#{"a".."e"}"
class B
  def initialize = @r = (0..9)
  def to_s = "B(#{@r})"
end
puts B.new.to_s
def show(x) = "[#{x}]"
puts show(3..4)
puts <<~T
  range #{(7..8)} end
T
puts "#{(..3)}"
