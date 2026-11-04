# spinel: int64
puts 0.digits.inspect
puts 1.digits.inspect
puts 9.digits.inspect
puts 10.digits.inspect
puts 12345.digits.inspect
puts 12345.digits(16).inspect
puts 255.digits(16).inspect
puts 255.digits(2).inspect
puts 1000000.digits(1000).inspect
puts 42.digits(10**30).inspect

x = 999999999999999999
puts x.digits.inspect
y = 12345678901234567890
puts y.digits.inspect
puts y.digits(16).inspect
puts (2**100).digits.inspect
puts (2**100).digits(2).length

def big_digits(n) = n.digits
puts big_digits(2**64).inspect

def poly(v) = v
p1 = poly(42)
puts p1.digits.inspect
p2 = poly(2**70)
puts p2.digits.inspect

begin
  5.digits(1)
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.digits(-1)
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  (-5).digits
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  (2**100 * -1).digits
rescue => e
  puts "#{e.class}: #{e.message}"
end

arr = [1, 22, 333, 4444].map { |n| n.digits }
puts arr.inspect

h = {a: 5}
puts h[:a].digits.inspect

def dstore(n)
  n.digits
end
puts dstore(7).inspect
