# `IO#read` on a pipe blocked its OS worker inside fread, so the green thread
# that would write to that pipe had nowhere to run: two threads passing a byte
# back and forth never completed on one worker (#4307). The readiness park was
# gated on the handle being a SOCKET; a pipe can block just as indefinitely.
#
# One worker is the point of the test -- with two, each thread gets its own OS
# thread and the kernel does the hand-off without the scheduler.
ENV["SPINEL_WORKERS"] = "1"

rounds = 50
a_r, a_w = IO.pipe
b_r, b_w = IO.pipe

t1 = Thread.new(a_w, b_r) do |w, r|
  n = 0
  while n < rounds
    w.write("x")
    r.read(1)
    n += 1
  end
  n
end

t2 = Thread.new(a_r, b_w) do |r, w|
  n = 0
  while n < rounds
    r.read(1)
    w.write("y")
    n += 1
  end
  n
end

p t1.value
p t2.value

# #gets takes the same park, and a pipe closed by its writer still reads EOF
c_r, c_w = IO.pipe
t3 = Thread.new(c_w) do |w|
  w.write("line one\n")
  w.write("line two\n")
  w.close
end
lines = []
while (l = c_r.gets)
  lines << l.chomp
end
t3.join
p lines

