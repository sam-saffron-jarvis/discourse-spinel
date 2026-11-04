# The caller's block is spliced at the yield inside an inlined method's loop.
# A `redo` in that block re-runs the loop body with the same element (it fell
# to `continue`, which is `next`), and a `break v` makes the CALL answer v.
def walk(xs, memo)
  xs.each { |x| yield x, memo }
  memo
end
tries = 0
r = walk([1, 2, 3], []) do |x, acc|
  tries += 1
  redo if x == 2 && tries < 5
  acc << x * 10
end
p r
p tries
p walk([1, 2, 3], []) { |x, m| break :bail if x == 2; m << x }
p walk([1, 2, 3], []) { |x, m| next if x == 2; m << x }
