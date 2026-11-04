# `next <expr>` in a block whose value the iterator discards: the expression
# still runs. The value has no slot to land in, so the emitter dropped it and
# left a bare `continue` that ran neither the push nor anything else (#4235).
found = []
[1].each { next found.push(1) }
p found

# more than one iteration, and a guard so only some take the next
seen = []
[1, 2, 3].each do |n|
  next seen.push(n) if n.odd?
  seen.push(n * 10)
end
p seen

# the same expression where the value IS used keeps working
doubled = [1, 2].map { |n| next n * 2 }
p doubled

# nested: the inner each discards, the outer map uses
outer = [1, 2].map do |n|
  acc = []
  [n].each { next acc.push(n) }
  acc
end
p outer

# a method call with a side effect on a receiver, not just a local
class Box
  attr_reader :log
  def initialize = @log = []
  def add(v) = @log.push(v)
end
b = Box.new
[7, 8].each { |n| next b.add(n) }
p b.log

# break and return in the same position already ran their expression
def find_first(list, sink)
  list.each { |n| break sink.push(n) }
  sink
end
p find_first([5, 6], [])
