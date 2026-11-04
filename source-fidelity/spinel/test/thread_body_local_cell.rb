# A local DECLARED inside a Thread.new block is one per thread. A local from the
# enclosing scope, written inside one, is shared with that scope. Both need the
# same machinery -- a heap cell, because a nested block captures them -- and the
# emitter told them apart by asking whether the local was celled, which is not
# the question: block locals are flattened into the enclosing scope's table, so
# `steps` below lives there too and looked exactly like the shared kind.
#
# It was captured, so every thread got the SAME cell: eight threads each
# counting to 3000 reported about 24,000 between them, plausibly and silently
# (#4410). The rule is now whether the enclosing scope TOUCHES the name outside
# the block.
#
# `require "set"` is what makes the inner block a real proc here rather than an
# inlined loop, which is what makes the local celled at all. Without it the
# program is correct on a broken tree, which is why the reporter found this
# only after a comment containing the word Set linked it in (#4411).
require "set"
S = Set.new([1, 2, 3])

# --- 1. declared in the thread body: one per thread ---

per_thread = (0...8).map do |t|
  Thread.new(t) do |tid|
    steps = 0
    300.times { |r| junk = (0...4).map { |k| "g#{r}-#{k}" }; steps += 1 }
    steps
  end
end
puts "per thread #{per_thread.map(&:value).inspect}"

# --- 2. an enclosing local, written inside a thread: shared with the scope ---
#        one thread, so the answer does not depend on the interleaving

shared = 0
seen = []
t = Thread.new do
  5.times { shared += 1 }
  3.times { |i| seen << i }
  shared
end
puts "thread value #{t.value}"
puts "shared after #{shared}"
puts "seen after #{seen.inspect}"

# --- 3. a second local beside the first, never touched by the nested block ---
#        it was already correct, and is here so a fix cannot trade one for it

mine = (0...4).map do |t|
  Thread.new(t) do |tid|
    tag = tid * 10
    count = 0
    50.times { count += 1 }
    [tag, count]
  end
end
puts "tagged #{mine.map(&:value).inspect}"
