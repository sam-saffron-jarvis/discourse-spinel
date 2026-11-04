# spinel: int64
# The shared table for out-of-int64 literals is filled at startup, not on
# first use: filled lazily, two threads reaching the same literal first
# raced on the slot (#4641). Every worker reaches the literal at once here,
# and a program whose only startup work is the table still gets it filled.
ts = 8.times.map { Thread.new { 0xFFFFFFFF_00000000 + 1 } }
p ts.map { |t| t.value }.uniq
p 0xFFFFFFFF_00000000 - 0xFFFFFFFF_00000000
