# A native class's Ruby-side defs are not poly-dispatch arms (#4504), so they
# must not suppress the builtin poly arms either. Merely creating an
# IO::Buffer made `h.values` on a poly Hash raise NoMethodError: the buffer's
# Ruby-side `def values` counted as a user definition, the builtin Hash arm
# stood down, and the dispatch was left with no arm at all.
b = IO::Buffer.new(8)
b.set_string("AB")

h = [{ "a" => 1, "b" => 2 }, nil][0]
p h.values
p h.keys

# The typed receiver still reaches the buffer's own Ruby defs, and the block
# form on a poly-carried buffer still dispatches to them.
p b.values(:U8, 0, 2)
pb = [b, nil][0]
acc = []
pb.each_byte(0, 2) { |x| acc << x }
p acc
