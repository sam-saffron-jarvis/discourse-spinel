# A threaded program that allocates on BOTH heaps, so the two collection
# triggers are both in play and SPINEL_GC_STATS reports both. The Makefile
# runs it three times and reads the trigger line back: each per-heap floor
# must move its own and leave the other where it was.
# The floors are applied when the worker pool is first sized, which is the
# first Thread.new. Anything allocated before that can collect under the
# BUILT-IN floor and print a [gc] line the floor arms would then read as
# "the knob did nothing". So the pool comes first.
Thread.new { 1 }.join

ts = []
4.times do |t|
  ts << Thread.new do
    strs = []
    objs = []
    i = 0
    while i < 60_000
      strs << "s#{i}-#{t}" * 4
      objs << [i, i + 1]
      strs.shift if strs.length > 2000
      objs.shift if objs.length > 2000
      i += 1
    end
    strs.length + objs.length
  end
end
total = 0
ts.each { |x| total += x.value }
puts total
