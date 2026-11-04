# `byteslice(range)` on a receiver typed poly emitted the SINGLE-INDEX helper
# whatever the argument was, so the Range reached the integer conversion: the
# range was built, cast to void and thrown away, and an unconditional
# "no implicit conversion of Range into Integer" ran in its place (#4308).
def poly_source(n)
  n > 0 ? "hello world" : nil
end

buffer = poly_source(1)
remaining = 6
buffer = buffer.byteslice(remaining..-1) || "" if buffer
p buffer

s = poly_source(1)
p s.byteslice(1..3) if s
p s.byteslice(0...5) if s
p s.byteslice(-5..) if s
p s.byteslice(..4) if s
p s.byteslice(20..25) if s
# the forms that already worked, kept so the arm order stays honest
p s.byteslice(3) if s
p s.byteslice(0, 5) if s
p s.byteslice(99) if s

nothing = poly_source(0)
p nothing.nil?
