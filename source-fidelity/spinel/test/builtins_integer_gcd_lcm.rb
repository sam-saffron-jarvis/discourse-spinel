# spinel: int64
puts 12.gcd(18)
puts 18.gcd(12)
puts (-12).gcd(18)
puts 12.gcd(-18)
puts (-12).gcd(-18)
puts 0.gcd(5)
puts 5.gcd(0)
puts 0.gcd(0)
puts 7.gcd(13)
puts 12.lcm(18)
puts 0.lcm(5)
puts 5.lcm(0)
puts (-4).lcm(6)
puts 4.lcm(-6)
puts 12.gcdlcm(18).inspect

x = 999999999999999999
y = 123456789012345
puts x.gcd(y)
puts x.lcm(y)
puts x.gcdlcm(y).inspect
z = 2**100
puts z.gcd(6)
puts z.lcm(6)
puts z.gcd(2**90)

def poly(v) = v
p1 = poly(24)
puts p1.gcd(36)
p2 = poly(2**80)
puts p2.gcd(6)

def wrap_gcd(n, m) = n.gcd(m)
puts wrap_gcd(15, 25)

begin
  5.gcd("x")
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.gcd(nil)
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.gcd(3.5)
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.gcd(3.0)
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.lcm(nil)
rescue => e
  puts "#{e.class}: #{e.message}"
end
# an Array/Hash argument used to fail to COMPILE rather than raise here
# (a required-parameter engine gap; see builtins/integer.rb's own comment)
begin
  5.gcd([1])
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.gcd({a: 1})
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.gcd(:a)
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  5.gcdlcm("x")
rescue => e
  puts "#{e.class}: #{e.message}"
end
