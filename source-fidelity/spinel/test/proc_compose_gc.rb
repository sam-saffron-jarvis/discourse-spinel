# The composed proc is anonymous at its call site, so only the trampoline's
# own root keeps its capture alive while the inner proc allocates and
# collects. Before the root this counted 40 of 40 wrong.
inc = ->(n) { n + 1 }
churn = ->(x) {
  parts = []
  40.times { |j| parts.push("c-#{x}-#{j}......................") }
  GC.start
  parts.length
}
bad = 0
40.times { |i| bad += 1 unless (churn >> inc).call(i) == 41 }
p bad
