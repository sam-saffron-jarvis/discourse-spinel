# A method whose value is a Bignum can also answer nil: an `if` with no else
# arm, a ternary's nil arm, a bare `return`. The int-to-bigint wrap on the
# return path turned the nil sentinel into a Bignum of INT64_MIN and the
# method answered -9223372036854775808, silently. NULL is the slot's nil, so
# every consumer of that slot has to read it as one: p, puts, print, to_s,
# inspect, interpolation, nil?, truthiness, and boxing into a poly slot.
BIG = 9223372036854775808

def no_else(x)
  return BIG if x == 9
  return (if x == 3 then 1 end)
end

def tern(x)
  return BIG if x == 9
  return (x == 3 ? 1 : nil)
end

def bare(x)
  return BIG if x == 9
  return nil if x == 1
  2
end

p no_else(1)
p no_else(3)
p tern(1)
p tern(3)
p bare(1)
p bare(2)
p no_else(9)

puts no_else(1).inspect
puts no_else(1).to_s.inspect
puts "interp: [#{no_else(1)}] [#{no_else(3)}]"
p no_else(1).nil?
p no_else(3).nil?
p(no_else(1) ? "t" : "f")
p(no_else(1) || 42)
p(no_else(3) || 42)
puts no_else(1)
print no_else(1)
print "|\n"

v = no_else(1)
p v
p v.nil?

h = {}
h[:k] = no_else(1)
h[:j] = no_else(3)
p h
p [no_else(1), no_else(3)]

# a genuine INT64_MIN is a value, not nil
def edge(x)
  return BIG if x == 9
  return -9223372036854775808
end
p edge(1)
p edge(1).nil?
