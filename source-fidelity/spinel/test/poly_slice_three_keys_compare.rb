# `Hash#slice` on a BOXED receiver, with three keys, on the right of `!=`.
#
# One emitter answers slice for a poly receiver at any key count: it branches
# at run time between Hash#slice(*keys) and the #[] re-entry, and both arms
# hand back an sp_RbVal. The inference rule that said "poly" for that shape
# was guarded on one or two keys. A three-key slice fell through to a typing
# that named a concrete hash kind, and the comparison then boxed a value that
# was already boxed -- `sp_box_nullable_obj((void *)<sp_RbVal>)` -- which clang
# refused (#4429). Where it came from: `assert_equal expected,
# record.attributes.slice("a", "b", "c")`, a stock Rails controller-test line.
#
# The inference guard matches the emitter's now. Two keys is kept beside three
# because two always worked and must go on working.
def pick(flag)
  if flag
    { "endpoint" => "e", "p256dh_key" => "p", "auth_key" => "a", "extra" => "x" }
  else
    [1, 2]
  end
end

params = { "endpoint" => "e", "p256dh_key" => "p", "auth_key" => "a" }
raise "assert_equal failed" if params != pick(true).slice("endpoint", "p256dh_key", "auth_key")
puts "three keys ok"

pair = { "endpoint" => "e", "p256dh_key" => "p" }
raise "two" if pair != pick(true).slice("endpoint", "p256dh_key")
puts "two keys ok"

# and the same slice in value position, four keys, printed
p pick(true).slice("endpoint", "p256dh_key", "auth_key", "extra")
