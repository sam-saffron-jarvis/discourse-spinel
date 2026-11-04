# `&:-@` and its siblings name real methods, but the textual &:sym rewrite
# scanned only identifier characters, so they had length zero and fell through
# to Prism -- where nothing lowers them, and the ENCLOSING call was reported
# undefined: `[1,2].map(&:-@)` said `map` has no such method (#4300).
#
# `_spx.-@` is not something Ruby can parse, so the unary symbols take the
# prefix spelling instead: `{ |_spx| -_spx }`.

p [1, 2].map(&:-@)
p [1, 2].map(&:+@)
p [1, 2, 3].map(&:~)
p [-1, 2, -3].map(&:-@)

# through the other block-carrying shapes the rewrite handles
p [3, 1, 2].sort_by(&:-@)
p [1, 2].each_with_object([]) { |x, acc| acc << -x }
p([1, 2].select { |x| x > 1 }.map(&:-@))

# an ordinary name symbol is unchanged
p [1, -2].map(&:abs)
p %w[a b].map(&:upcase)

# a binary operator symbol still goes to the reduce lowering
p [1, 2, 3].reduce(:+)
p [1, 2, 3].inject(:*)
