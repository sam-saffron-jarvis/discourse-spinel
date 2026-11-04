# `r[k] ||= v`, `r[k] &&= v` and `r[k] op= v` on a boxed r read and store
# through the runtime's generic element access, which knew only the builtin
# containers: an object with its own [] / []= read every element as nil and
# lost every store. Here the object reaches a block kept as a Proc, the
# shape of an aggregate function handed a context.

class Ctx
  def initialize = @h = {}
  def [](k) = @h[k]
  def []=(k, v)
    @h[k] = v
  end
end

class Agg
  def initialize(&blk) = @blk = blk
  def feed(ctx, v) = @blk.call(ctx, v)
end

a = Agg.new do |fn, value|
  next if value.nil?
  fn[:n] ||= 0
  fn[:sum] ||= 0.0
  fn[:n] += 1
  fn[:sum] += value
  fn[:max] = value if fn[:max].nil? || value > fn[:max]
  fn[:seen] &&= true
end
ctx = Ctx.new
[1.5, nil, 2.5].each { |v| a.feed(ctx, v) }
p [ctx[:n], ctx[:sum], ctx[:max], ctx[:seen]]

# a Hash handed to the same block still works
h = {}
[3, 4].each { |v| a.feed(h, v) }
p h
