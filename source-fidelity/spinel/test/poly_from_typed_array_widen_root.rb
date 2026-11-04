# Widening a typed array into a poly slot goes through
# sp_PolyArray_from_int_array, sp_PolyArray_from_str_array or
# sp_PolyArray_from_float_array. Each allocates its poly result and then
# reads the typed array's elements, and when that array comes straight from
# a method call nothing holds it but the C argument. The typed
# sp_*Array_dup helpers root their argument across the same allocation;
# these three did not. On bc32aa72 this test's first line reads
# [129, 266, 1, 17] in a plain build and the stress build crashes; with the
# three helpers rooting their argument it reads [0, 0, 0, 0] both ways.
def ints = (1..400).map { |i| i * 10 }
def floats = (1..400).map { |i| i * 1.5 }
def strs = (1..40).map { |i| "s#{i}" }
def frozen_ints = (1..40).map { |i| i * 10 }.freeze

bad_int = 0
4000.times do
  x = ints
  x << "tail"
  bad_int += 1 if x.size != 401 || x[0] != 10 || x[399] != 4000 || x[400] != "tail"
end

bad_float = 0
4000.times do
  x = floats
  x << "tail"
  bad_float += 1 if x.size != 401 || x[0] != 1.5 || x[399] != 600.0 || x[400] != "tail"
end

bad_str = 0
4000.times do
  x = strs
  x << 7
  bad_str += 1 if x.size != 41 || x[0] != "s1" || x[39] != "s40" || x[40] != 7
end

bad_concat = 0
4000.times do
  x = [0, "z"]
  x.concat(ints)
  bad_concat += 1 if x.size != 402 || x[2] != 10 || x[401] != 4000
end

p [bad_int, bad_float, bad_str, bad_concat]

x = ints
x << :done
p [x.size, x[0], x[399], x[400]]
y = floats
y << :done
p [y.size, y[0], y[399], y[400]]
z = strs
z << :done
p [z.size, z[0], z[39], z[40]]
w = [0, "z"]
w.concat(strs)
p [w.size, w[0], w[2], w[41]]
p x.frozen?
x = frozen_ints
p x.frozen?
