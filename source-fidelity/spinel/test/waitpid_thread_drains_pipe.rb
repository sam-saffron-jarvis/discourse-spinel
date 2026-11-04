# Process.waitpid2 must not hold the OS worker while another green thread has
# work to do. A started thread is pinned to its worker, so a blocking wait
# stalls every thread pinned there -- including the one that has to make
# progress before the wait can return.
#
# The shape is `spin build --verbose` (#4381): the parent spawns the compiler
# with its stderr on a pipe, a reader thread drains it, and the parent waits.
# The child fills the pipe and blocks writing; the reader cannot be scheduled;
# the child never exits and the wait never returns. It needs more output than
# the pipe buffer holds -- 20k lines went through, 30k deadlocked.
rd, wr = IO.pipe
pid = Process.spawn("/bin/sh", "-c", "seq 1 200000 1>&2", :err => wr)
wr.close
n = 0
reader = Thread.new do
  while rd.gets
    n += 1
  end
  n
end
_, status = Process.waitpid2(pid)
lines = reader.value
rd.close
p [status.success?, lines]

# Kernel#system waits the same way and had the same blocking wait.
sibling = Thread.new do
  i = 0
  while i < 50_000
    i += 1
  end
  i
end
ok = system("seq 1 100000 > /dev/null")
p [ok, sibling.value]

# One thread only: the blocking wait is kept, and still answers.
pid2 = Process.spawn("/bin/sh", "-c", "exit 3")
_, st2 = Process.waitpid2(pid2)
p [st2.success?, st2.exitstatus]
