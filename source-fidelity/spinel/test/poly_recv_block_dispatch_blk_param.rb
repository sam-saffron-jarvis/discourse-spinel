# A poly-receiver call with a literal block dispatches per class by inlining
# the callee into each arm -- but a callee that consumes its block through a
# declared `&blk` rather than `yield` is not an inlining target: it has a
# standalone function. Its arm was opened and left EMPTY (`case 1: { break; }`)
# and the call silently vanished, with no diagnostic. Mixed sets are the
# reachable shape, and so is an all-`&blk` set (a poly `Net::HTTP#request`
# with a block, which is where this was found).
class Yielder
  def handle(x)
    yield "Y:#{x}"
  end
end

class Declarer
  def handle(x, &blk)
    blk.call("D:#{x}") unless blk.nil?
  end
end

items = [Yielder.new, Declarer.new]
items.each do |o|
  o.handle(1) { |v| puts v }
end

# the same through an index accessor, the other way into this dispatch
items[1].handle(2) { |v| puts v }
