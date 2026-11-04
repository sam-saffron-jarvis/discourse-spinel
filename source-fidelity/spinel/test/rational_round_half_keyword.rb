# `round(half:)` on a Rational, typed and boxed. The Rational arms read the
# mode as a literal `:even` / `:down` / `:up` written at the call and treated
# every other spelling as no mode at all -- a String, a Symbol out of a
# variable and a `**` source were all silently the half-up default, with the
# mode sitting right there unread. A digit count alongside the keyword had no
# arm to answer it, and the boxed path validated the mode and then handed the
# receiver to a helper that rounds half up regardless.

r = Rational(5, 2)      # a tie at the decimal point
q = Rational(25, 1)     # a tie one place above it
f = Rational(15, 100)   # a tie one place below it
m  = :even
ms = "even"
md = "down"

# a String says what a Symbol says, and so does a mode known only at run time
p r.round(half: :even)
p r.round(half: ms)
p r.round(half: m)
p r.round(half: md)
p q.round(-1, half: :even)
p q.round(-1, half: ms)
p q.round(-1, half: md)
p f.round(1, half: :even)
p f.round(1, half: md)

# a digit count alongside the keyword: a positive precision keeps the
# Rational, at or below the decimal point the answer is an Integer
p r.round(0, half: :even)
p r.round(1, half: :even)
p r.round(-1, half: :even)
# ... and a count known only at run time chooses there
n1 = 1
nm1 = -1
n0 = 0
p f.round(n1, half: ms)
p q.round(nm1, half: ms)
p r.round(n0, half: ms)

# a `**` source
h = { half: :even }
p r.round(**h)
p q.round(-1, **h)
p f.round(1, **h)

# `round` takes `half:` and nothing else, and a mode that is neither a Symbol
# nor a String names itself
begin
  r.round(foo: 1)
rescue ArgumentError => e
  puts "foo: #{e.message}"
end
begin
  r.round(half: 1)
rescue ArgumentError => e
  puts "one: #{e.message}"
end
begin
  r.round(half: :bogus)
rescue ArgumentError => e
  puts "bogus: #{e.message}"
end
begin
  r.round(0, half: :bogus)
rescue ArgumentError => e
  puts "zero: #{e.message}"
end

# only #round takes a mode. CRuby's words for a Rational are its own, and
# with a digit count as well it is the arity it complains about first.
[:ceil, :floor, :truncate].each do |op|
  begin
    r.send(op, half: :up)
    puts "#{op}: no raise"
  rescue TypeError => e
    puts "#{op}: #{e.message}"
  end
end
begin
  r.ceil(1, half: :up)
rescue ArgumentError => e
  puts "ceil2: #{e.message}"
end

# the same value through a boxed slot has to answer the same: the boxed arm
# read and validated the mode, then dropped it on the way to the rounding
pr = [Rational(5, 2), nil][0]
pq = [Rational(25, 1), nil][0]
pf = [Rational(15, 100), nil][0]
p pr.round(half: :even)
p pr.round(half: m)
p pr.round(half: ms)
p pr.round(half: md)
p pq.round(-1, half: :even)
p pq.round(-1, half: ms)
p pf.round(1, half: :even)
p pr.round(**h)
p pq.round(-1, **h)
begin
  pq.round(foo: 1)
rescue ArgumentError => e
  puts "pfoo: #{e.message}"
end
begin
  pq.floor(half: :up)
rescue TypeError => e
  puts "pfloor: #{e.message}"
end
begin
  pq.floor(1, half: :up)
rescue ArgumentError => e
  puts "pfloor2: #{e.message}"
end

# the receiver, the digit count and every keyword value are evaluated before
# the call decides anything
def probe(tag, v)
  puts "probe #{tag}"
  v
end
begin
  r.round(probe(:pos, 0), half: probe(:kw, :bogus))
rescue ArgumentError => e
  puts "order: #{e.message}"
end
begin
  r.ceil(half: probe(:ckw, :up))
rescue TypeError => e
  puts "corder: #{e.message}"
end
