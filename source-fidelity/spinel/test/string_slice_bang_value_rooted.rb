# String#slice!(start, len) used as a value handed back a string the collector
# had already freed. The emitter built the removed part into a plain C local,
# then rebuilt the receiver with three allocating calls (two sp_str_sub_range
# and an sp_str_concat) before handing the local back. Any of the three could
# collect, and the local was not a root, so the caller read freed memory: an
# empty string, a wrong length, or a SIGSEGV in whatever touched it next. The
# removed part is a rooted temp for the rest of the block now, in the two arms
# that build it with sp_str_sub_range: slice!(start, len) and slice!(range) /
# slice!(i). The slice!(str) and slice!(/re/) arms hand back a string something
# else already roots (the argument, the match registers) and were not affected.
#
# The width has to vary: with a constant width malloc hands the freed block
# straight back for an identical string and the bug is hidden. 200000 rounds
# let a natural collection land in the window: before the fix this printed
# 26, 31 and 26 here (macOS arm64) and died with SIGSEGV on Linux arm64; under
# SPINEL_GC_STRESS=1 the first loop lost 532 of 20000. After: 0 everywhere.
buf = +""
bad = 0
i = 0
while i < 200000
  want = (i + 1) % 50 + 1
  buf << ("x" * want)
  line = buf.slice!(0, want)
  bad += 1 if line.nil? || line.bytesize != want
  i += 1
end
p bad

# the ivar-receiver arm: a read buffer that hands out one piece at a time
class Rbuf
  def initialize
    @rbuffer = String.new
  end

  def fill(s)
    @rbuffer << s
  end

  def consume(want)
    return nil if @rbuffer.empty?
    @rbuffer.slice!(0, want)
  end
end

r = Rbuf.new
bad = 0
i = 0
while i < 200000
  want = (i + 1) % 50 + 1
  r.fill("y" * want)
  line = r.consume(want)
  bad += 1 if line.nil? || line.bytesize != want
  i += 1
end
p bad

# the one-argument arm: slice!(range), same construction
buf = +""
bad = 0
i = 0
while i < 200000
  want = (i + 1) % 50 + 1
  buf << ("z" * want)
  line = buf.slice!(0...want)
  bad += 1 if line.nil? || line.bytesize != want
  i += 1
end
p bad
