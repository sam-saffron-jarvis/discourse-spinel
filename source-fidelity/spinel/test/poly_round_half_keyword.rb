# `round(half:)` on a BOXED receiver. The tie-break mode is a keyword, not a
# positional argument: read as one it reached the digits slot and raised "no
# implicit conversion of Hash into Integer", while the typed Float and Integer
# paths have honoured the mode all along. A value that went through a container
# has to answer what the same value answers when it did not.
x = [8388609.0, nil][0]
p x.round(half: :even)
y = [2.5, nil][0]
p y.round(half: :even)
p y.round(half: :up)
p y.round(half: :down)
p y.round(half: nil)
p y.round
z = [2.345, nil][0]
p z.round(2, half: :even)
p z.round(2, half: :up)
p z.round(2)
n = [-15.0, nil][0]
p n.round(-1, half: :even)
i = [25, nil][0]
p i.round(half: :even)
p i.round(-1, half: :even)

# a mode read out of a container is chosen at run time
m = [:even, nil][0]
p y.round(half: m)

# only #round takes a tie-break mode; the others reject the keyword as CRuby does
[:floor, :ceil, :truncate].each do |op|
  begin
    y.send(op, half: :even)
    puts "#{op}: no raise"
  rescue TypeError => e
    puts "#{op}: #{e.message}"
  end
end
begin
  y.round(half: :bogus)
rescue ArgumentError => e
  puts "bogus: #{e.message}"
end

# `round` takes `half:` and nothing else: another key is the unknown-keyword
# ArgumentError, not a silently defaulted mode.
begin
  y.round(foo: 1)
rescue ArgumentError => e
  puts "foo: #{e.message}"
end
begin
  y.round(foo: 1, bar: 2)
rescue ArgumentError => e
  puts "foobar: #{e.message}"
end
# a mode that is neither a Symbol nor a String names itself in the message,
# where mapping it to the default sentinel had rounded half up in silence
begin
  y.round(half: 1)
rescue ArgumentError => e
  puts "one: #{e.message}"
end
# CRuby reads a String as readily as a Symbol
p y.round(half: "even")
# an Integer receiver validates the mode too, even where it answers itself
begin
  i.round(0, half: :bogus)
rescue ArgumentError => e
  puts "int0: #{e.message}"
end

# the receiver, the positional argument and every keyword value are evaluated
# before the call decides it cannot be made
def probe(tag)
  puts "probe #{tag}"
  1
end
begin
  y.ceil(half: probe(:kw))
rescue TypeError => e
  puts "ceil: #{e.message}"
end
begin
  y.ceil(probe(:pos), half: probe(:kw2))
rescue ArgumentError => e
  puts "ceil2: #{e.message}"
end

# a `**` source: the keys it carries are read at run time, where the mode was
# left silently defaulted because the key set could not be seen
hk = { half: :even }
p y.round(**hk)
p i.round(-1, **hk)
p y.round(1, **hk)
begin
  y.round(**{ zz: 1 })
rescue ArgumentError => e
  puts "splat: #{e.message}"
end
