# `File.open` on a FIFO waits in the kernel for the other end, with no
# descriptor to wait on. A green thread is pinned to its OS worker, so that one
# syscall stalled every green thread pinned there, including the one counting a
# Thread#join timeout down: the first arm here printed nothing at all before
# the fix, not even the join's answer, and the process never terminated (#4394).
#
# The first arm is a shape whose answer the blocking open could not produce. The
# regular-file arm is the control: it does not go through the FIFO path at all
# and has to read exactly as it always did.

dir = "/tmp/sp_fifo_test_#{Process.pid}"
Dir.mkdir(dir)

def mkfifo(path)
  system("mkfifo #{path}") or raise "mkfifo failed"
  path
end

# --- 1. a reader with no writer: the join times out and the program ends ---

lonely = mkfifo(File.join(dir, "lonely"))
reader = Thread.new do
  File.open(lonely, "r") { |f| f.each_line { |l| l } }
end
sleep 0.1
puts "join #{reader.join(0.3).inspect}"
puts "status #{reader.status.inspect}"

# Arms that pass DATA through a FIFO are deliberately absent, and their absence
# is the interesting part. A reader and a writer exchanging three lines through
# one, and a writer that opens first and is released by a later reader, both
# answer CRuby on Linux and both hang on macOS -- on a tree with NO runtime
# change at all, which #4406 established by running that arm alone against
# master. So FIFO data flow between two green threads is broken on macOS
# independently of anything here, and it is written down in docs/limitations.md
# rather than pinned by a test that could not pass. Put those arms back with
# the fix for it.

# --- 4. control: a regular file is not a FIFO and opens as it always did ---

plain = File.join(dir, "plain.txt")
File.write(plain, "ordinary\n")
puts "plain #{File.read(plain).chomp.inspect}"
puts "missing #{begin; File.open(File.join(dir, "absent")); "no raise"; rescue => e; e.class.to_s; end}"

[lonely, plain].each { |p| File.delete(p) rescue nil }
Dir.rmdir(dir) rescue nil
puts "end"
