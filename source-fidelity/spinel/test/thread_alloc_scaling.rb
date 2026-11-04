# Allocation-heavy work on several threads used to spend more CPU than it
# saved: the per-worker string trigger fires on ONE worker's bytes against the
# threshold, while sp_stw_collect's early-out wants the AGGREGATE over
# N * threshold. A worker that crossed first was refused, nothing reset its
# bytes, and it asked again on the very next allocation -- 7.2 million asks
# for 941 collections, each taking the global scheduler lock (#4334).
#
# This is a correctness-shaped test for a performance bug: what it asserts is
# that the answers are right at every worker count, which is what the fix must
# not break. The cost itself is measured outside the suite.
n = 4
iters = 20000
threads = []
i = 0
while i < n
  threads << Thread.new(i) do |k|
    last = ""
    j = 0
    while j < iters
      last = "row-" + (k * iters + j).to_s
      j += 1
    end
    last
  end
  i += 1
end
vals = threads.map { |t| t.value }
p vals.size
p vals[0]
p vals[n - 1]

# The collector still runs. The fix delays a REFUSED ask by one threshold's
# worth of allocation; it must not delay the collection itself, so a loop that
# allocates far past the threshold has to advance the cycle counter.
before = GC.stat["cycle"]
keep = ""
m = 0
while m < 400000
  keep = "s" + m.to_s
  m += 1
end
p keep
p GC.stat["cycle"] > before
