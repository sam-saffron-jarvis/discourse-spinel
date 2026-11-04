# A bound Method read out of a poly slot is called through the per-target
# thunk its bind site synthesized when the stamped ABIs do not fit the call:
# a Float parameter or return, an omitted optional filled from its default
# (evaluated with the Method's receiver as self), a rest packed from the
# surplus, a top-level and a class-method target, a count the signature
# cannot bind answering CRuby's ArgumentError. The thunk converts at the
# boundary: an argument of another kind than the compiled parameter is a
# TypeError there (the one line that differs from CRuby, which would fail
# inside the body). (#4542, makenowjust)
class K
  def initialize(s) = @s = s
  def addf(a, b) = a + b * 1.5
  def opt(a, b = 10, c = a + 1) = [a, b, c, @s]
  def rest(a, *r) = [a, r]
  def flag(x) = x ? "yes" : "no"
  def sym(s) = s.to_s.upcase
  def name = @s
  def self.mk(n) = K.new("k#{n}")
end
def top(x, y = 2.5) = x * y
k = K.new("kk")
p k.addf(0.5, 1)   # a visible call: a is a Float, b an Integer
p k.flag(false), k.sym(:q)
slots = [k.method(:addf), k.method(:opt), k.method(:rest), k.method(:flag), k.method(:sym), k.method(:name), method(:top), K.method(:mk)]
p slots[0].call(1, 2)
p slots[0].call(1.5, 2)
p slots[1].call(1)
p slots[1].call(1, 2)
p slots[1].call(1, 2, 3)
p slots[2].call(1)
p slots[2].call(1, 2, 3)
p slots[3].call(nil), slots[3].call(1)
p slots[4].call(:abc)
p slots[5].call
p slots[6].call(4)
p slots[6].call(4, 0.5)
p slots[7].call(3).name
begin
  slots[0].call("x", 2)
rescue TypeError => e
  puts e.message
end
begin
  slots[1].call
rescue ArgumentError => e
  puts e.message
end
begin
  slots[0].call(1, 2, 3)
rescue ArgumentError => e
  puts e.message
end
p slots.map { |m| m.arity }
pr = slots[1].to_proc
p pr.call(7)
p slots[0].to_proc.call(2, 2)
