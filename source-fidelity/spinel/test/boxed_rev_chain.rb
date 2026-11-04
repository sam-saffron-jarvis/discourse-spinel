# A blockless reverse_each and a chain on a receiver whose class is only known
# at run time (an Array, Hash, Range, Struct, Enumerator or user Enumerable
# read out of a mixed container) answer the Enumerator the typed receiver
# answers.
def attempt(name)
  yield
rescue => e
  puts "#{name}: #{e.class}"
end

S = Struct.new(:a, :b)
class Nums
  include Enumerable
  def each
    yield 1
    yield 2
    yield 4
  end
end

a = [[1, 2, 3], 0][0]
h = [{a: 1, b: 2}, 0][0]
r = [(1..3), 0][0]
s = [S.new(5, 6), 0][0]
n = [Nums.new, 0][0]
en = [[7, 8].each, 0][0]

attempt(:rev_array) { p a.reverse_each.to_a }
attempt(:rev_hash) { p h.reverse_each.to_a }
attempt(:rev_range) { p r.reverse_each.to_a }
attempt(:rev_struct) { p s.reverse_each.to_a }
attempt(:rev_user) { p n.reverse_each.to_a }
attempt(:rev_enum) { p en.reverse_each.to_a }
attempt(:rev_class) { p a.reverse_each.class }
attempt(:rev_size) { p a.reverse_each.size }
attempt(:rev_next) { e = a.reverse_each; p [e.next, e.next, e.next] }
attempt(:rev_map) { p a.reverse_each.map { |x| x * 10 } }
attempt(:rev_with_index) { p a.reverse_each.with_index.to_a }
attempt(:rev_each) { a.reverse_each.each { |x| print x }; puts }
attempt(:rev_sym_proc) { p [a, [9]].map(&:reverse_each).map(&:to_a) }
attempt(:rev_block) { p a.reverse_each { |x| x }.class }

attempt(:chain_array) { p a.chain([4]).to_a }
attempt(:chain_none) { p a.chain.to_a }
attempt(:chain_two) { p a.chain([4], (5..6)).to_a }
attempt(:chain_hash) { p h.chain([[:c, 3]]).to_a }
attempt(:chain_range) { p r.chain(a).to_a }
attempt(:chain_struct) { p s.chain([1]).to_a }
attempt(:chain_user) { p n.chain(n).to_a }
attempt(:chain_enum) { p en.chain([9]).to_a }
attempt(:chain_nested) { p a.chain([9]).chain([10]).to_a }
attempt(:chain_rev) { p a.reverse_each.chain(a.reverse_each).to_a }
attempt(:chain_class) { p a.chain([4]).class }
attempt(:chain_size) { p a.chain([4]).size }
attempt(:chain_each) { a.chain([9]).each { |x| print x }; puts }

def rev(v) = v.reverse_each.to_a
def cat(v) = v.chain([0]).to_a
p [rev([1, 2]), rev({a: 1}), rev((1..3))]
p [cat([1, 2]), cat({a: 1}), cat((1..2))]
