# each_with_object is defined in Ruby (builtins/enumerable.rb) and compiled
# with the program: every receiver kind, the blockless Enumerator form, the
# break and redo the caller's block may do, and the memo's own type coming
# out typed. The engine work the definition drew out sits in the tests beside
# this one (block_given_tail_typed_per_call, empty_array_arg_typed_by_pushes,
# yield_splice_redo_and_break).
p [1, 2, 3].each_with_object([]) { |x, m| m << x * 2 }
p [1, 2, 3].each_with_object({}) { |x, m| m[x] = x * x }
p({ a: 1, b: 2 }.each_with_object([]) { |(k, v), m| m << "#{k}=#{v}" })
p({ a: 1, b: 2 }.each_with_object({}) { |pair, m| m[pair[1]] = pair[0] })
p (1..4).each_with_object([]) { |x, m| m.unshift(x) }
p ["a", "b"].each_with_object(+"") { |x, m| m << x.upcase }
p [1, 2, 3].each_with_index.each_with_object([]) { |(x, i), m| m << x * i }
p [1, 2, 3].each.with_object([]) { |x, m| m << x + 1 }

# blockless: an Enumerator over [element, memo] pairs, and its each runs the
# method with the block
e = [1, 2].each_with_object([])
p e.class
p e.to_a
p([1, 2, 3].each_with_object([]).each { |x, m| m << x })

# a class that includes Enumerable
class Bag
  include Enumerable
  def initialize(*xs) = @xs = xs
  def each(&) = @xs.each(&)
end
p Bag.new(3, 4).each_with_object([]) { |x, m| m << x * 10 }

# a receiver known only at run time
def pick(i) = [[1, 2], { k: 1 }][i]
p pick(0).each_with_object([]) { |x, m| m << x }
p pick(1).each_with_object([]) { |x, m| m << x }

# break and redo in the caller's block
p [1, 2, 3].each_with_object([]) { |x, m| break :bail if x == 2; m << x }
tries = 0
p [1, 2, 3].each_with_object([]) { |x, m| tries += 1; redo if x == 2 && tries < 4; m << x }
p tries

# a class that defines its own each_with_object keeps it
class Own
  def each_with_object(memo) = memo << :own
end
p Own.new.each_with_object([]) { |x, m| m << x }
