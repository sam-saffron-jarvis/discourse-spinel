# Every timed park must be woken by its descriptor, not by its deadline. The
# readiness set moved into the kernel (#4306/#4317), and the failure mode a
# persistent registration risks is exactly this: a park that arms nothing, or
# an event nobody is listening for, and the thread sits until its timeout.
#
# Pairs pass a byte back and forth; the peer always writes BEFORE the other
# side parks, so a select that times out is a lost wake and nothing else. The
# first cut of the event backend lost 11 of 16 here, about one run in twenty.
# Each thread counts its own misses -- a shared counter would be a race in the
# test itself.
pairs  = 4
rounds = 150
keep = []
threads = []
i = 0
while i < pairs
  a_r, a_w = IO.pipe
  b_r, b_w = IO.pipe
  keep << a_r << a_w << b_r << b_w
  threads << Thread.new(a_w, b_r) do |w, r|
    n = 0
    miss = 0
    while n < rounds
      w.write("x")
      miss += 1 if IO.select([r], nil, nil, 5).nil?
      r.read(1)
      n += 1
    end
    miss
  end
  threads << Thread.new(a_r, b_w) do |r, w|
    n = 0
    miss = 0
    while n < rounds
      miss += 1 if IO.select([r], nil, nil, 5).nil?
      r.read(1)
      w.write("y")
      n += 1
    end
    miss
  end
  i += 1
end
total = 0
threads.each { |t| total += t.value }
p total
p pairs * rounds * 2

# A park with no deadline at all has nothing to fall back on, so it is the
# shape a lost wake stops outright.
r2, w2 = IO.pipe
reader = Thread.new(r2) { |io| io.read(1) }
writer = Thread.new(w2) do |io|
  20.times { Thread.pass }
  io.write("z")
end
p reader.value
writer.join
