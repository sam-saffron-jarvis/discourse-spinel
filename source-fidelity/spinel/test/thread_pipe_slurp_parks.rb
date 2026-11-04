# `IO#read` with no count asks fread for a whole buffer at a time, and fread
# does not come back until it has that many bytes or EOF. On a pipe that is a
# sit in the kernel between the writer's chunks, holding the OS worker: a green
# thread slurping a pipe another green thread is still writing to never
# finished on one worker, because the writer had nowhere to run (#4307).
ENV["SPINEL_WORKERS"] = "1"

r, w = IO.pipe
got = nil
reader = Thread.new(r) { |io| got = io.read }
writer = Thread.new(w) do |io|
  io.write("hello ")
  5.times { Thread.pass }
  io.write("world")
  io.close
end
[reader, writer].each { |t| t.join }
p got

# a payload bigger than one stdio buffer, over several refills
chunk = "x" * 10000
r2, w2 = IO.pipe
big = nil
reader2 = Thread.new(r2) { |io| big = io.read }
writer2 = Thread.new(w2) do |io|
  10.times do
    io.write(chunk)
    Thread.pass
  end
  io.close
end
[reader2, writer2].each { |t| t.join }
p big.length
p big == chunk * 10

# nothing written, closed at once
r3, w3 = IO.pipe
t3 = Thread.new(w3) { |io| io.close }
p r3.read
t3.join

# The write side is the same defect: a write into a FULL pipe sits in the
# kernel holding the OS worker, and the reader that would drain it is a green
# thread on that same worker -- so it never runs. 100KB through a 64KB pipe
# deadlocked about one run in fifty before the write park.
r4, w4 = IO.pipe
block = "y" * 20000
drained = nil
reader4 = Thread.new(r4) { |io| drained = io.read }
writer4 = Thread.new(w4) do |io|
  5.times { io.write(block) }
  io.close
end
[reader4, writer4].each { |t| t.join }
p drained.length
p drained == block * 5
