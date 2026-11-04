# A Struct read out of a container (a mixed Array here) answers the
# member-array names the typed Struct answers: a blockless each and each_pair,
# values_at and values.
def attempt(name)
  yield
rescue => e
  puts "#{name}: #{e.class}"
end

S = Struct.new(:a, :b, :c)
P = Struct.new(:x, :y)
s = [S.new(1, 2, 3), 0][0]
q = [P.new("u", :v), 0][0]
n = [S.new(nil, 2, nil), 0][0]

attempt(:each_to_a) { p s.each.to_a }
attempt(:each_class) { p s.each.class }
attempt(:each_next) { e = s.each; p [e.next, e.next] }
attempt(:each_size) { p s.each.size }
attempt(:each_str) { p q.each.to_a }
attempt(:each_nil) { p n.each.to_a }
attempt(:each_block) { p s.each { |x| x }.class }
attempt(:pair_to_a) { p s.each_pair.to_a }
attempt(:pair_class) { p s.each_pair.class }
attempt(:pair_str) { p q.each_pair.to_a }
attempt(:pair_block) { p s.each_pair { |k, v| }.class }
attempt(:values_at) { p s.values_at(0, 2) }
attempt(:values_at_neg) { p s.values_at(-1, 0) }
attempt(:values_at_str) { p q.values_at(1) }
attempt(:values_at_nil) { p n.values_at(0, 1) }
attempt(:values) { p s.values }
attempt(:values_str) { p q.values }
attempt(:values_nil) { p n.values }
attempt(:values_copy) { v = s.values; v << 9; p s.values }
attempt(:array_each) { p [[7, 8], 0][0].each.to_a }
attempt(:array_values_at) { p [[7, 8, 9], 0][0].values_at(0, 2) }
attempt(:hash_values) { p [{k: 1}, 0][0].values }
attempt(:nil_values) { p [nil, 0][0].values }
attempt(:int_values_at) { p [5, nil][0].values_at(0) }
def members_of(v) = v.each.to_a
p [members_of(S.new(4, 5, 6)), members_of([1]), members_of({z: 0})]
def at(v) = v.values_at(0)
p [at(S.new(4, 5, 6)), at([1]), at({0 => :z})]
