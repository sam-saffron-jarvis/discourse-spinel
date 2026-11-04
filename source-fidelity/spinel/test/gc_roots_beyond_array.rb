# A recursion whose live roots outnumber the GC root array (65536 entries)
# keeps every root: the roots past the array go to an overflow segment
# instead of being dropped, which let the collector free the strings the
# live frames still named. A generated frame registers one entry for all of
# its locals, so the twelve nested iterators here, each rooting the array
# it walks for the call inside it, are what put a frame past the array by
# depth 6000. The collection at the bottom runs while the deepest frames'
# roots are past the array, the strings built after it take the slots a
# dropped root would have freed, and every frame checks its own strings on
# the way back up. (CRuby's own limit is a few thousand frames of this
# shape, so the answers are pinned: the depth-th successors of "aaaaa".)
def g(s, n)
  if n == 0
    GC.start
    junk = (1..100000).map { |z| z.to_s * 2 }
    return junk.size > 0 ? s : nil
  end
  r = nil
  [s.succ].each { |a| [a.succ].each { |b| [b.succ].each { |c| [c.succ].each { |d|
    [d.succ].each { |e| [e.succ].each { |f| [f.succ].each { |h| [h.succ].each { |i|
      [i.succ].each { |j| [j.succ].each { |k| [k.succ].each { |l| [l.succ].each { |m|
        r = g(m, n - 1)
        raise "lost at #{n}: #{[s, a, b, c, d, e, f, h, i, j, k, l, m].inspect}" unless
          m == s.succ.succ.succ.succ.succ.succ.succ.succ.succ.succ.succ.succ && s.size == 5
      } } } }
    } } } }
  } } } }
  r
end
[100, 7000].each { |n| puts g("aaaaa", n) }
GC.start
puts g("aaaaa", 7000)
