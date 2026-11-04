# A splice into a typed array whose source is a poly array: a boxed value
# holding one (`bytes = bytes.first(n)` on a parameter that is sometimes not
# an array), or a local typed as one. The source's elements replace the
# span, one for one. As a boxed value it was taken for a scalar, so the span
# shrank to one element; as a local it was refused at compile time.

def place(dst, off, bytes)
  bytes = bytes.first(3)
  dst[off, bytes.length] = bytes
end

a = Array.new(8, 0)
place(a, 2, [1, 2, 3, 4])
p a
place(a, 5, [7, 8, 9, 10].select(&:positive?))
p a
p a.length
place(a, 0, "xyz") if a.empty?

# a local poly array as the source, into an Integer array
def shrink(dst, b)
  src = b.first(3)
  dst[1, 1] = src
  dst
end

def grow(dst, b)
  src = b.first(2)
  dst[1, 4] = src
  dst
end

def by_range(dst, b)
  src = b.first(2)
  dst[2..3] = src
  dst
end

def endless(dst, b)
  src = b.first(2)
  dst[4..] = src
  dst
end

def at_end(dst, b)
  src = b.first(2)
  dst[dst.length, 0] = src
  dst
end

def empty_source(dst, b)
  src = b.first(0)
  dst[1, 2] = src
  dst
end

def as_value(dst, b)
  src = b.first(2)
  x = (dst[0, 1] = src)
  p x
  dst
end

def boxed_value(dst, b)
  b = b.first(2)
  x = (dst[0, 1] = b)
  p x
  dst
end

p shrink(Array.new(5, 0), [1, 2, 3, 4])
p shrink(Array.new(4, 0), [1, nil, 3])
p grow(Array.new(6, 0), [1, 2, 3])
p by_range(Array.new(6, 0), [1, 2, 3])
p endless(Array.new(6, 0), [1, 2, 3])
p at_end(Array.new(2, 0), [1, 2, 3])
p empty_source(Array.new(5, 0), [1, 2])
p as_value(Array.new(3, 0), [1, 2, 3])
p boxed_value(Array.new(3, 0), [1, 2, 3])
if a.empty?
  [shrink([0], "s"), grow([0], 1), by_range([0], 1.5), endless([0], :s),
   at_end([0], 1), empty_source([0], 1), as_value([0], 1), boxed_value([0], 1)]
end

# into a String array and a Float array
def shrink_s(dst, b)
  b = b.first(3)
  dst[1, 1] = b
  dst
end

def range_s(dst, b)
  src = b.first(2)
  dst[2..3] = src
  dst
end

def shrink_f(dst, b)
  b = b.first(3)
  dst[1, 1] = b
  dst
end

def endless_f(dst, b)
  src = b.first(2)
  dst[4..] = src
  dst
end

p shrink_s(Array.new(5, "-"), %w[a b c d])
p shrink_s(Array.new(4, "-"), ["a", nil, "c"])
p range_s(Array.new(6, "-"), %w[a b c])
p shrink_f(Array.new(5, 0.0), [1.5, 2.5, 3.5])
p shrink_f(Array.new(4, 0.0), [1.5, nil])
p endless_f(Array.new(6, 0.0), [1.5, 2.5])
if a.empty?
  [shrink_s(["-"], 1), range_s(["-"], 1), shrink_f([0.0], 1), endless_f([0.0], 1)]
end

# a boxed scalar in the span's place goes in as one element, nil as nil
def put_i(dst, v)
  dst[1, 2] = v
  dst
end

def put_s(dst, v)
  dst[1, 2] = v
  dst
end

def put_f(dst, v)
  dst[1, 2] = v
  dst
end

p put_i(Array.new(4, 0), 9)
p put_i(Array.new(4, 0), nil)
p put_s(Array.new(4, "-"), "s")
p put_s(Array.new(4, "-"), nil)
p put_f(Array.new(4, 0.0), 2.5)
p put_f(Array.new(4, 0.0), nil)
[put_i([0], [1]), put_s(["-"], ["s"]), put_f([0.0], [1.5])] if a.empty?

# the EasyFlash shape: 8K chips placed into a flash image
BANK = 0x2000

def place_bank(flash, offset, bytes)
  bytes = bytes.first(BANK)
  flash[offset, bytes.length] = bytes
end

low = Array.new(8 * BANK, 0xff)
chips = (0...4).map { |n| Array.new(BANK) { |i| (n + i) & 0xff } }
chips.each_with_index { |data, n| place_bank(low, n * BANK, data + [0]) }
place_bank(low, 0, "chip") if low.empty?
p low.length
p low[3 * BANK, 3]
p low[4 * BANK, 3]

# a nil array value (Array#assoc on a miss) is one nil element
def by_assoc(dst, pairs, k)
  dst[1, 1] = pairs.assoc(k)
  dst
end
p by_assoc([0, 0, 0], [[9, 1], ["a", 2]], 9)
p by_assoc([0, 0, 0], [[9, 1], ["a", 2]], 7)
