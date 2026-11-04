# A Struct or Data constructed only by a bare `new(...)` or `self.new(...)`
# in one of its own class methods: those calls typed no member, so every
# member was laid out sp_RbVal (#4842). infer-test greps the emitted layout.

M = Struct.new(:op, :n) do
  def self.make(i) = new(i.odd? ? :lda : :sta, i)
end
m = M.make(3)
p m.op
p m.n + 1
N = Struct.new(:a, :b) do
  def self.make(i) = self.new(i, "s#{i}")
end
x = N.make(4)
p x.a * 2
p x.b
D = Data.define(:v) do
  def self.of(i) = new(v: i * 3)
end
p D.of(2).v
