# `round(half:)` on a TYPED receiver, the mirror of poly_round_half_keyword.
# The typed arms read the mode as a Symbol NAME the compiler could see, so
# every other spelling went wrong: a String or a `**` source would not even
# compile, and an Integer receiver silently rounded half up while holding a
# perfectly good mode. A mode is a value, not a name.

# a String says what a Symbol says
p 2.5.round(half: "even")
p 2.5.round(half: "up")
p 2.5.round(half: "down")
p 25.round(-1, half: "even")
p 2.345.round(2, half: "even")

# so does a mode that is only known at run time -- the Integer path ignored
# these outright and answered the half-up default
m = :even
p 2.5.round(half: m)
p 25.round(-1, half: m)
ms = "even"
p 2.5.round(half: ms)
p 25.round(-1, half: ms)
p 2.675.round(2, half: ms)
n = 2
p 2.345.round(n, half: ms)
n0 = 0
p 2.5.round(n0, half: ms)

# a `**` source: its keys are read at run time rather than left unseen
h = { half: :even }
p 2.5.round(**h)
p 25.round(-1, **h)
p 2.5.round(1, **h)
p 2.5.round(**{})
# the later spelling wins, as it does in the hash the call really builds
up = { half: :up }
p 2.5.round(half: :even, **up)
p 2.5.round(**up, half: :even)

# `round` takes `half:` and nothing else
begin
  2.5.round(foo: 1)
rescue ArgumentError => e
  puts "foo: #{e.message}"
end
begin
  2.5.round(foo: 1, bar: 2)
rescue ArgumentError => e
  puts "foobar: #{e.message}"
end
begin
  2.5.round("a" => 1)
rescue ArgumentError => e
  puts "str: #{e.message}"
end
begin
  2.5.round(**{ x: 1 })
rescue ArgumentError => e
  puts "splat: #{e.message}"
end
# with a digit count the Integer path reached the rounding without ever
# looking at the keyword
begin
  15.round(-1, foo: 1)
rescue ArgumentError => e
  puts "intfoo: #{e.message}"
end

# a mode that is neither a Symbol nor a String names itself in the message
begin
  2.5.round(half: 1)
rescue ArgumentError => e
  puts "one: #{e.message}"
end
begin
  15.round(-1, half: 1)
rescue ArgumentError => e
  puts "intone: #{e.message}"
end

# Integer#round WITHOUT a digit count answers the receiver without reading the
# keywords at all -- CRuby validates the mode only once digits are there
p 1.round(half: :bogus)
p 1.round(foo: 1)
p 1.round(**{ foo: 1 })
begin
  1.round(0, half: :bogus)
rescue ArgumentError => e
  puts "int0: #{e.message}"
end

# only #round takes a tie-break mode; with a digit count as well it is the
# arity CRuby complains about first
begin
  2.5.floor(half: :up)
rescue TypeError => e
  puts "floor: #{e.message}"
end
begin
  1.ceil(half: :up)
rescue TypeError => e
  puts "intceil: #{e.message}"
end
begin
  2.5.truncate(1, half: :up)
rescue ArgumentError => e
  puts "trunc2: #{e.message}"
end
begin
  1.floor(1, half: :up)
rescue ArgumentError => e
  puts "intfloor2: #{e.message}"
end

# the receiver, the digit count and every keyword value are evaluated before
# the call decides it cannot be made
def probe(tag, v)
  puts "probe #{tag}"
  v
end
begin
  2.5.round(probe(:pos, 0), half: probe(:kw, :bogus))
rescue ArgumentError => e
  puts "order: #{e.message}"
end
# ... even where the keywords are then ignored entirely
p 1.round(half: probe(:ignored, :bogus))

# the reject paths evaluate the keyword values too: CRuby builds the hash
# before the call decides it cannot be made
begin
  2.5.ceil(half: probe(:f_kw, :up))
rescue TypeError => e
  puts "fceil: #{e.message}"
end
begin
  2.5.ceil(probe(:f_pos, 1), half: probe(:f_kw2, :up))
rescue ArgumentError => e
  puts "fceil2: #{e.message}"
end
begin
  7.ceil(half: probe(:i_kw, :up))
rescue TypeError => e
  puts "iceil: #{e.message}"
end
begin
  7.ceil(probe(:i_pos, 1), half: probe(:i_kw2, :up))
rescue ArgumentError => e
  puts "iceil2: #{e.message}"
end

# a keyword hash longer than any fixed buffer: the reader used to cap the
# elements it looked at, and a hash past the cap was read as EMPTY -- its
# `half:` silently dropped and its unknown keywords let through. CRuby names
# the unknown ones (it lists all; the message here keeps the first eight) and
# honours a mode that arrives after many others.
def many_unknown
  2.5.round(half: :even, k1: 1, k2: 2, k3: 3, k4: 4, k5: 5, k6: 6, k7: 7, k8: 8,
            k9: 9, k10: 10, k11: 11, k12: 12, k13: 13, k14: 14, k15: 15, k16: 16,
            k17: 17, k18: 18, k19: 19, k20: 20, k21: 21, k22: 22, k23: 23, k24: 24,
            k25: 25, k26: 26, k27: 27, k28: 28, k29: 29, k30: 30, k31: 31, k32: 32,
            k33: 33, k34: 34, k35: 35)
rescue ArgumentError => e
  e.message[0, 24]
end
puts "many: #{many_unknown}"
