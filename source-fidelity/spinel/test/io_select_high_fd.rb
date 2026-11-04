# `IO#wait_readable` and IO.select refused a descriptor at or past FD_SETSIZE,
# because the select(2) bitmap check stood in FRONT of the park that has no
# such bound. A server with two descriptors per connection crosses 1024 at a
# few hundred connections, and the thread died before it could close the
# socket -- so the client saw neither an answer nor an EOF (#4314).
#
# Readiness on one descriptor, and on a set with no PRIORITY member, is a poll
# now. The priority set keeps select, where the bound is real.
#
# Reaching fd 1024 needs a descriptor soft limit above it -- the test runner
# raises it, best effort. Where it cannot be raised the loop stops early and
# the same calls run at a lower descriptor: still a valid check, just not the
# one that would have caught this. So the fd itself is not asserted.
keep = []
rd = nil
opened = 0
while (rd.nil? || rd.fileno < 1024) && opened < 3000
  begin
    r, w = IO.pipe
  rescue StandardError
    break
  end
  keep << r << w
  opened += 2
  rd = r
end
wr = keep[keep.index(rd) + 1]

p rd.wait_readable(0.02).nil?
wr.write("x")
p rd.wait_readable(0.5).nil?
p rd.read(1)
p IO.select([rd], nil, nil, 0.02).nil?
wr.write("y")
p IO.select([rd], nil, nil, 0.5)[0].length
p rd.read(1)

# a high descriptor together with a low one, over the multi-IO path
low = keep[0]
lowr = keep[1]
lowr.write("z")
res = IO.select([rd, low], nil, nil, 0.5)
p [res[0].length, res[0][0].equal?(low)]
p low.read(1)

# the shapes that already worked, so the arm order stays honest
p IO.select(nil, [wr], nil, 0.5)[1].length
p IO.select([rd], nil, nil, 0).nil?
p IO.select(nil, nil, nil, 0.01)
