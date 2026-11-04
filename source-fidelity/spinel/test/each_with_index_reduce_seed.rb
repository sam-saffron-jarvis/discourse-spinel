# The each_with_index reduce fold renders its block's tail with the prelude
# still pointed at the CALLER. A tail that hoists -- `acc + [pair]` builds the
# one-element array as statements -- put that construction ahead of the loop,
# where it read the pair local before any iteration had set it. Every element
# then folded the same stale value: [[9,9],[0,0],[0,0]] (#4297).
#
# The loop body is a statement expression, so the tail's own statements are
# valid inside it; the prelude points there now.
#
# Each case uses its own block-parameter names: a name shared between reduces
# whose seeds have different types shares one slot, which is a separate
# defect and not what this pins.

p [10, 20].each_with_index.reduce([[9, 9]]) { |acc, pair| acc + [pair] }
p [10, 20].each_with_index.reduce([[9, 9]]) { |a2, (value, index)| a2 + [[index, value]] }
p [5, 6, 7].each_with_index.reduce([[0, 0]]) { |a3, p3| a3 + [p3] }

# a tail that needs no hoist was never affected
p [10, 20].each_with_index.reduce(0) { |a4, (v, i)| a4 + v + i }
