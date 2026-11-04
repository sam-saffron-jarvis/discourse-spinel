# `worker` is written once, by the very expression whose nested block reads it,
# and it is never named in the Thread body's own statements. The nested block is
# lifted to a proc of its own (its receiver is untyped), so the capture scan
# looked for a write in the frame that directly encloses it -- the Thread's --
# and the only write is one frame further out, at the top level. That refused
# the program as an uncaptured outer variable (#4349).
require "set"

seen = nil
worker = Thread.new do
  pending = nil
  begin
    pending = pending.each { seen = worker.class.to_s }
  rescue NoMethodError
    seen = "nil has no each"
  end
end
worker.join
p seen

# the same read reached through two lifted frames, with a value to check
def untyped(x) = x

label = "row"
rows = []
outer = Thread.new do
  src = untyped([1, 2])
  src.each do |i|
    inner = untyped([i])
    inner.each { |j| rows << "#{label}#{j}" }
  end
end
outer.join
p rows.sort
