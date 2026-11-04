# `gsub` with a block walks its SUBJECT across every match, and every match
# allocates: the substring before it, whatever the block builds, the append
# into the accumulator. The accumulator was rooted and the subject was not, so
# a collection landing inside the block freed the bytes the scan was reading.
# The receiver here is built by the same statement, which is what leaves the
# hoisted copy without another holder.
#
# The second fault this pins is one level down. The answer comes back through
# `sp_String`'s payload, and a slot holding that escaped `const char *` is the
# only thing keeping the HANDLE alive -- but the object marker for a payload
# was on the collector's skip list, so the handle went unreferenced and its
# finaliser freed the bytes the slot still named.
#
# Both fail as a SIGSEGV rather than a wrong answer, deterministically at this
# size on the default collector, so the test is the run completing at all. The
# live set and the subject length are what put a collection inside the walk;
# at a tenth of either, both faults answer correctly.
LIVE = []
i = 0
while i < 3000
  LIVE << "live-#{i}-#{"x" * 60}"
  i += 1
end

VARS = {}
i = 0
while i < 600
  VARS["K#{i}"] = "value-#{i}"
  i += 1
end

def build(n)
  t = String.new
  i = 0
  while i < n
    t << "<td>{{ K#{i} }}</td>|"
    i += 1
  end
  t
end

RE = /{{(.*?)}}/
acc = 0
r = 0
while r < 4
  out = build(20000).gsub(RE) { VARS.fetch($1.strip, "") }
  acc = (acc + out.bytesize) & 0xFFFFFFFF
  r += 1
end
puts "acc #{acc} live #{LIVE.size}"
