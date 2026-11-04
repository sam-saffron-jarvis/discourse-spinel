# `a[i, n]` on a poly receiver that turns out to hold something with no `[]`
# at all. Only String, Array and Integer (bit range) answer a two-argument
# slice; a Symbol answers with its *name* sliced into a String; nil, a Float
# and the booleans have no `[]` and CRuby says so by name. (A Symbol with a
# Range index is a separate path -- sp_poly_index_poly routes a Range only to
# an array receiver -- so it is left out here.) The nil arm matters
# twice over, because a nil that reached an int slot is stored as the slot's
# sentinel and used to slice out of it as if it were the integer.
def slice2(x) = x[0, 4]
def slice_range(x) = x[0..1]

p slice2([:sym, nil][0])
p slice2(["abcdef", 1][0])
p slice2([[1, 2, 3], 1][0])
p slice2([7, "x"][0])
p slice_range(["abcdef", 1][0])

[[nil, 1], [1.5, "x"], [true, 1], [false, 1]].each do |cell|
  begin
    p slice2(cell[0])
  rescue NoMethodError => e
    puts e.message
  end
  begin
    p slice_range(cell[0])
  rescue NoMethodError => e
    puts e.message
  end
end

# the nil that lives in an int slot: the array is all-Integer but for the nil,
# so the element type is an int whose sentinel means nil -- slicing it once
# answered the sentinel's bit range instead of raising.
ints = [1, 2, nil]
ints.each do |v|
  begin
    p v[0, 4]
  rescue NoMethodError => e
    puts e.message
  end
end
