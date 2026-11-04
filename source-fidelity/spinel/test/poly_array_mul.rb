# Array#* on a boxed Array: an Integer repeats, a String joins (#4834).
# It fell to sp_poly_mul's bad-operand report, a TypeError.
x = [[0, 1], 1][0]
p x * 2
p x * ","
y = [%w[a b], 1][0]
p y * 2
p y * "-"
z = [[1.5, :s, "t", nil], 1][0]
p z * 2
p z * "|"
p x * 0
begin
  x * -1
rescue ArgumentError => e
  puts e.message
end
class H
  def initialize; @a = [1, 2]; @a = nil if ARGV.size > 3; end
  def go; @a *= 2; @a; end
end
p H.new.go
