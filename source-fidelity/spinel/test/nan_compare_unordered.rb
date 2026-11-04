# NaN is unordered: it is neither less than, equal to, nor greater than
# anything, itself included. A three-way compare cannot say that, so the boxed
# comparisons read (gt - lt) == 0 as "equal" and answered true for <= and >=,
# 0 for <=>, and picked a winner for max where CRuby raises.
nan = [0xffc00000].pack("V").unpack1("e")
vals = [nan, -0.0, 1.0, 2]
box = [vals, nil][0]
a = box[0]
c = box[2]
d = box[3]
p [a < c, a <= c, a > c, a >= c, a == c]
p [c < a, c <= a, c > a, c >= a, c == a]
p [d < a, d <= a, d > a, d >= a]
p [a < a, a <= a, a >= a, a == a]
p(a <=> c)
p(c <=> a)
begin
  p [a, c].max
rescue ArgumentError
  puts "max: ArgumentError"
end

# NaN is unordered only against the numeric tower. Against anything else the
# pair is genuinely incomparable and CRuby raises, so the short-circuit that
# answers false must not reach nil, a String or a Symbol -- and the Bignum and
# Rational arms convert their float operand before comparing, which must not
# be reached with a NaN either (the conversion is undefined, and one that
# completes reports the pair comparable).
big = [2**70, nil][0]
rat = [Rational(1, 3), nil][0]
others = [[nil, "nil"], ["x", "String"], [:sym, "Symbol"], [big, "Bignum"], [rat, "Rational"]]
others.each do |o, what|
  begin
    puts "NaN < #{what}: #{a < o}"
  rescue ArgumentError
    puts "NaN < #{what}: ArgumentError"
  end
end
others.each { |o, what| puts "NaN <=> #{what}: #{(a <=> o).inspect}" }
begin
  p [a, big].max
rescue ArgumentError
  puts "max with Bignum: ArgumentError"
end
