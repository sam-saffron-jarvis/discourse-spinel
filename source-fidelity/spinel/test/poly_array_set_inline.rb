# A store into a poly array takes the inline path when the index is in bounds
# and the array is live; every other store (negative index, a gap, an append,
# a frozen array) keeps the cold path's behaviour. Arrays of true/false are
# the common poly array, so their methods are covered alongside.

class Mask
  attr_reader :bits

  def initialize(n)
    @bits = Array.new(n, false)
  end

  def set(i) = @bits[i] = true
  def clear! = @bits.fill(false)
  def on?(i) = @bits[i]
end

m = Mask.new(6)
m.set(1)
m.set(4)
p m.bits
p m.on?(1), m.on?(2)
m.clear!
p m.bits

a = Array.new(4, true)
a[0] = false
a[-1] = false
p a
a[4] = true
p a
a[7] = false
p a
p a.length
begin
  a[-20] = true
rescue IndexError => e
  puts "IndexError: #{e.message}"
end

f = [true, false, true].freeze
begin
  f[0] = false
rescue => e
  puts e.class
end
p f

b = [false, false, false, false, false]
b.fill(true, 1, 2)
p b
b.fill(false)
b[2] = true
p b.index(true), b.count(true), b.include?(true)
p b.any?, b.all?, b.none?
p b.map { |x| !x }
b.each_with_index { |x, i| print i if x }
puts
p b == [false, false, true, false, false]
p b.dup.push(false).length, b.length
p b.to_a.inspect, b.join(",")
p b.select { |x| x }.size
begin
  b.sort
rescue => e
  puts e.class
end
b << 3
p b
b[0] = "x"
p b

i = 0
sieve = Array.new(30, true)
sieve[0] = false
sieve[1] = false
i = 2
while i * i < 30
  if sieve[i]
    j = i * i
    while j < 30
      sieve[j] = false
      j += i
    end
  end
  i += 1
end
p (0...30).select { |k| sieve[k] }

objs = Array.new(3, nil)
GC.start
GC.start
k = 0
while k < 3
  objs[k] = "s#{k}"
  k += 1
end
junk = nil
200_000.times { |j| junk = [j, "j#{j}"] }
GC.start
p objs
