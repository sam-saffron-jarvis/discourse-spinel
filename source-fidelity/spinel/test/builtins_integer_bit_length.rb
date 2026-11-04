# spinel: int64
[0, 1, -1, 2, -2, 5, -5, 255, 256, -255, -256, 1023, 1024, -1024, 2**62, -(2**62), 2**63-1].each do |n|
  puts "#{n}: #{n.bit_length}"
end

x = 999999999999999999
puts x.bit_length
y = -999999999999999999
puts y.bit_length
z = 2**100
puts z.bit_length
puts (-z).bit_length
puts (2**100 - 1).bit_length

def poly(v) = v
p1 = poly(255)
puts p1.bit_length
p2 = poly(2**80)
puts p2.bit_length

def wrap_bl(n) = n.bit_length
puts wrap_bl(1000)
