# A Float whose integer value escapes int64, on its way into a slot that holds
# sp_int. The bare cast is C UB, and not the harmless kind: it saturated at
# -O0 and, from -O1, the optimizer took the UB as a promise and deleted the
# statement around it -- `p (2.0**70).floor` printed NOTHING and exited 0.
# Every route raises now. CRuby answers the Bignum; that promotion is a
# separate matter, but a loud error is not an undefined value.
big = 2.0**70
def poly(x) = x

[:floor, :ceil, :round, :truncate, :to_i, :to_int].each do |m|
  begin
    big.send(m)
    puts "#{m}: NO RAISE"
  rescue => e
    puts "#{m}: #{e.class}"
  end
end
begin; big.floor;      rescue => e; puts "floor direct: #{e.class}"; end
begin; big.ceil;       rescue => e; puts "ceil direct: #{e.class}"; end
begin; big.round;      rescue => e; puts "round direct: #{e.class}"; end
begin; big.truncate;   rescue => e; puts "truncate direct: #{e.class}"; end
begin; big.to_i;       rescue => e; puts "to_i direct: #{e.class}"; end
begin; Integer(big);   rescue => e; puts "Integer(): #{e.class}"; end
begin; big.floor(-1);  rescue => e; puts "floor(-1): #{e.class}"; end
n = -1
begin; big.round(n);   rescue => e; puts "round(runtime -1): #{e.class}"; end
begin; big.div(1.0);   rescue => e; puts "div: #{e.class}"; end
begin; big.divmod(1.0); rescue => e; puts "divmod: #{e.class}"; end
begin; poly(big).floor;    rescue => e; puts "poly floor: #{e.class}"; end
begin; poly(big).ceil;     rescue => e; puts "poly ceil: #{e.class}"; end
begin; poly(big).round;    rescue => e; puts "poly round: #{e.class}"; end
begin; poly(big).truncate; rescue => e; puts "poly truncate: #{e.class}"; end
begin; poly(big).round(-1); rescue => e; puts "poly round(-1): #{e.class}"; end
begin; (-big).floor;   rescue => e; puts "negative floor: #{e.class}"; end

# a non-finite value is still FloatDomainError, named as CRuby names it
inf = 1.0 / 0.0
nan = inf - inf
begin; inf.floor;  rescue => e; puts "inf floor: #{e.class}: #{e.message}"; end
begin; (-inf).ceil; rescue => e; puts "-inf ceil: #{e.class}: #{e.message}"; end
begin; nan.round;  rescue => e; puts "nan round: #{e.class}: #{e.message}"; end
begin; poly(inf).floor; rescue => e; puts "poly inf floor: #{e.class}: #{e.message}"; end

# and nothing in range moved
p 3.7.floor, 3.2.ceil, 3.5.round, (-3.7).truncate, 3.7.to_i, Integer(3.9)
p (-3.7).floor, (-3.2).ceil, (-2.5).round, 2.5.round
p 1234.5678.floor(2), 1234.5678.round(-2), 1234.5678.ceil(-2), 1234.5678.truncate(-2)
d = -2
p 1234.5678.round(d)
p 7.5.div(2.0), 7.5.divmod(2.0)
p poly(3.9).floor, poly(3.1).ceil, poly(3.5).round, poly(-3.9).truncate, poly(1234.5678).round(-2)

# A boxed Bignum receiver's to_i: #4665 left it raising here pending #2024,
# and moved out of poly_bignum_integer_surface when promote learned to answer
# it. promote_float_to_int pins the answer on the other side.
def poly_v(x) = x
p poly_v("s")
begin; poly_v(18446744073709551615).to_i; rescue => e; puts "boxed bignum to_i: #{e.class}"; end

# The tie-break keyword cannot be what decides whether a value is
# representable: `round(half:)` raises here exactly as the bare `round` does.
f = 1e20
m = :even
begin; f.round(half: :even); rescue RangeError => e; puts "kw: #{e.message}"; end
begin; f.round(half: m); rescue RangeError => e; puts "kwdyn: #{e.message}"; end
begin; f.round(half: "even"); rescue RangeError => e; puts "kwstr: #{e.message}"; end
# a BOXED receiver answers the Bignum in either mode, keyword or not
v = [1e20, nil][0]
p v.round
p v.round(half: :even)
p v.round(half: m)
p v.round(half: "even")
