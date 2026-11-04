# `shift(n)` / `pop(n)` on a boxed receiver when a program class also defines
# the name: the call was typed as Array's removed subarray while the user arm
# answered something else, so the C did not compile; and a receiver that
# really was an Array had no arm and raised NoMethodError (#4831).

class Shifter
  def initialize = @v = 1
  def shift(n) = @v <<= n
  def pop(n) = @v >> n
end
def pick(flag) = flag ? Shifter.new : [1, 2, 3, 4, 5]
[true, false].each do |flag|
  x = pick(flag)
  p x.shift(2)
  p x.pop(1)
end
class Feed
  def initialize = @pending = nil
  def load(text) = @pending = text.bytes
  def chunk = @pending.shift(2)
end
class Q
  def shift(n) = [n, n]
end
f = Feed.new
f.load("abcd")
p f.chunk
p [Q.new, [9, 8, 7]].map { |o| o.shift(1) }
