# A block its callee keeps as a Proc (`def initialize(&blk) = @blk = blk`)
# is called later by code the block's own site cannot see, so `fn[:k] = v`
# in its body says nothing about what `fn` is. The parameter was guessed a
# Symbol-keyed Hash from that write, and an object with its own [] / []=
# passed in later was read as a hash's table: a segfault.

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

# 1. an object with its own [] / []=
a = Agg.new do |fn, value|
  next if value.nil?
  fn[:n] = (fn[:n] || 0) + 1
  fn[:sum] = (fn[:sum] || 0.0) + value
end
ctx = Ctx.new
[1.5, nil, 2.5].each { |v| a.feed(ctx, v) }
p [ctx[:n], ctx[:sum]]

# 2. a plain write only
b = Agg.new { |fn, value| fn[:last] = value }
ctx2 = Ctx.new
b.feed(ctx2, 7)
p ctx2[:last]

# 3. a real Hash through the same shape
h = {}
b.feed(h, 8)
p h
