# respond_to? on a Struct read out of a container answered false for the
# names the Struct carries from its core class (values, to_a, to_h, members,
# size, [], the Enumerable names), true only for the synthesized each,
# each_pair and each_with_index and for the names every object answers;
# the typed Struct answered false for values_at and dig. A boxed Enumerable
# includer, a boxed Comparable and a boxed Data were wrong the same way, and
# a typed Data answered true for a Struct's values, size, length, [] and []=.
S = Struct.new(:a, :b)
D = Data.define(:x, :y)
class C
  include Enumerable
  def each
    yield 1
    yield 2
  end
end
class V
  include Comparable
  attr_reader :n
  def initialize(n) = @n = n
  def <=>(o) = n <=> o.n
end

t = S.new(1, 2)
s = [S.new(1, 2), 0][0]
n = [S.new(1, 2), nil][0]
%i[a a= values values_at dig to_a to_h members size length [] []= each each_pair each_with_index deconstruct deconstruct_keys select map sort_by min include? first zip class frozen? nil? no_such].each do |m|
  print m, " "
end
puts
p [t.respond_to?(:a), t.respond_to?(:a=), t.respond_to?(:values), t.respond_to?(:values_at), t.respond_to?(:dig), t.respond_to?(:to_a), t.respond_to?(:to_h), t.respond_to?(:members), t.respond_to?(:size), t.respond_to?(:length), t.respond_to?(:[]), t.respond_to?(:[]=), t.respond_to?(:each), t.respond_to?(:each_pair), t.respond_to?(:each_with_index), t.respond_to?(:deconstruct), t.respond_to?(:deconstruct_keys), t.respond_to?(:select), t.respond_to?(:map), t.respond_to?(:sort_by), t.respond_to?(:min), t.respond_to?(:include?), t.respond_to?(:first), t.respond_to?(:zip), t.respond_to?(:class), t.respond_to?(:frozen?), t.respond_to?(:nil?), t.respond_to?(:no_such)]
p [s.respond_to?(:a), s.respond_to?(:a=), s.respond_to?(:values), s.respond_to?(:values_at), s.respond_to?(:dig), s.respond_to?(:to_a), s.respond_to?(:to_h), s.respond_to?(:members), s.respond_to?(:size), s.respond_to?(:length), s.respond_to?(:[]), s.respond_to?(:[]=), s.respond_to?(:each), s.respond_to?(:each_pair), s.respond_to?(:each_with_index), s.respond_to?(:deconstruct), s.respond_to?(:deconstruct_keys), s.respond_to?(:select), s.respond_to?(:map), s.respond_to?(:sort_by), s.respond_to?(:min), s.respond_to?(:include?), s.respond_to?(:first), s.respond_to?(:zip), s.respond_to?(:class), s.respond_to?(:frozen?), s.respond_to?(:nil?), s.respond_to?(:no_such)]
p [n.respond_to?(:values), n.respond_to?(:values_at), n.respond_to?(:each_pair), n.respond_to?(:map), n.respond_to?(:no_such)]

# the other member of the container keeps its own answer
i = [0, S.new(1, 2)][0]
p [i.respond_to?(:values), i.respond_to?(:abs), i.respond_to?(:times), i.respond_to?(:each)]
q = [nil, S.new(1, 2)][0]
p [q.respond_to?(:values), q.respond_to?(:to_a), q.respond_to?(:nil?)]
r = [[3], S.new(1, 2)][0]
p [r.respond_to?(:values), r.respond_to?(:first), r.respond_to?(:each), r.respond_to?(:map)]

# a Struct with a method of its own beside the core names
T = Struct.new(:c) do
  def values = [:mine]
  def extra = 1
end
u = [T.new(1), 0][0]
p [u.respond_to?(:values), u.respond_to?(:extra), u.respond_to?(:values_at), u.respond_to?(:c)]
p u.values

# a boxed Enumerable includer and a boxed Comparable answer the module's names
c = [C.new, 0][0]
p [c.respond_to?(:each), c.respond_to?(:map), c.respond_to?(:sort_by), c.respond_to?(:to_a), c.respond_to?(:min), c.respond_to?(:values)]
v = [V.new(1), 0][0]
p [v.respond_to?(:<=>), v.respond_to?(:<), v.respond_to?(:between?), v.respond_to?(:clamp), v.respond_to?(:n), v.respond_to?(:map)]

# a Data answers its own names and not a Struct's
e = D.new(x: 1, y: 2)
d = [D.new(x: 1, y: 2), 0][0]
p [e.respond_to?(:x), e.respond_to?(:members), e.respond_to?(:to_h), e.respond_to?(:with), e.respond_to?(:deconstruct_keys), e.respond_to?(:values), e.respond_to?(:values_at), e.respond_to?(:size), e.respond_to?(:length), e.respond_to?(:[]), e.respond_to?(:[]=)]
p [d.respond_to?(:x), d.respond_to?(:members), d.respond_to?(:to_h), d.respond_to?(:with), d.respond_to?(:deconstruct_keys), d.respond_to?(:values), d.respond_to?(:values_at), d.respond_to?(:size), d.respond_to?(:length), d.respond_to?(:[]), d.respond_to?(:[]=)]

# through a method parameter that is a Struct, an Array, a Data and an Enumerable includer
def asks(o) = [o.respond_to?(:values), o.respond_to?(:size), o.respond_to?(:with), o.respond_to?(:members)]
p asks(S.new(1, 2))
p asks([1])
p asks(D.new(x: 1, y: 2))
p asks(C.new)
