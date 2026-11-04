# A store into a frozen Array raises FrozenError naming the receiver: its
# inspect ends the message, as in CRuby, for every element kind (#4924).
f = [true, false, true].freeze
begin
  f[0] = false
rescue => e
  puts e.message
end
g = [1, 2].freeze
begin
  g[0] = 3
rescue => e
  puts e.message
end
h = [1, "a"].freeze
begin
  h[0] = 3
rescue => e
  puts e.message
end
k = ["x", "y"].freeze
begin
  k << "z"
rescue FrozenError => e
  puts e.message
  p e.receiver.equal?(k)
end
