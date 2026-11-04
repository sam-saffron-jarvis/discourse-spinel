# Process.spawn with a filename redirection. The file named by `in:` is
# opened read-only, so the child reads it and its contents survive; `out:`
# and `err:` are created and truncated as before. The descriptors a spawn
# opens for those names are its own to close: the parent's copies go once the
# child has them, and on every raise the runtime makes, while an IO the
# caller handed in stays open. Every count below is /dev/fd after minus before, so the expected
# value is 0 on any machine.

require "tmpdir"

def fds
  Dir.children("/dev/fd").size
end

Dir.mktmpdir do |dir|
  input = File.join(dir, "input.txt")
  output = File.join(dir, "output.txt")
  errout = File.join(dir, "err.txt")
  missing = File.join(dir, "absent.txt")
  nodir = File.join(dir, "nodir", "x.txt")

  # 1) in: a filename -- the child reads it, and it is unchanged afterwards.
  File.write(input, "valuable input\n")
  File.write(output, "stale output that must go\n")
  pid = Process.spawn("/bin/cat", in: input, out: output)
  _, status = Process.waitpid2(pid)
  p status.exitstatus
  p File.read(input)
  p File.read(output)

  # 2) err: a filename is created and truncated, as out: is.
  File.write(errout, "stale\n")
  pid = Process.spawn("/bin/sh", "-c", "echo oops >&2", err: errout)
  _, status = Process.waitpid2(pid)
  p status.exitstatus
  p File.read(errout)

  # 3) A missing input path raises the Errno CRuby raises and creates nothing.
  begin
    Process.spawn("/bin/cat", in: missing)
    puts "no raise"
  rescue SystemCallError => e
    puts e.class
    puts e.message.sub(dir, "DIR")
  end
  p File.exist?(missing)

  # 4) An output path in a missing directory raises the same way.
  begin
    Process.spawn("/usr/bin/true", out: nodir)
    puts "no raise"
  rescue SystemCallError => e
    puts e.class
    puts e.message.sub(dir, "DIR")
  end

  # 5) Twenty spawns with filename redirections leave the fd table as it was.
  before = fds
  20.times do
    pid = Process.spawn("/bin/cat", in: input, out: output)
    Process.waitpid2(pid)
  end
  p fds - before

  # 6) So does a spawn whose exec fails after the redirections were opened.
  before = fds
  20.times do
    begin
      pid = Process.spawn("/no/such/command", in: input, out: output)
      Process.waitpid2(pid)
    rescue Errno::ENOENT
    end
  end
  p fds - before

  # 7) And one whose second redirection fails to open after the first did.
  before = fds
  20.times do
    begin
      Process.spawn("/bin/cat", in: input, out: nodir)
    rescue Errno::ENOENT
    end
  end
  p fds - before

  # 8) An IO the caller opened is still open and writable after the spawn.
  f = File.open(output, "w")
  pid = Process.spawn("/bin/echo", "from child", out: f)
  Process.waitpid2(pid)
  p f.closed?
  f.puts "from parent"
  f.close
  p File.read(output)

  # 9) out: and err: both filenames in one spawn: two owned descriptors.
  pid = Process.spawn("/bin/sh", "-c", "echo to-out; echo to-err >&2", out: output, err: errout)
  Process.waitpid2(pid)
  p File.read(output)
  p File.read(errout)

  # 10) A caller's IO in one slot and a filename in another: only the
  # filename's descriptor is the spawn's to close.
  f = File.open(output, "w")
  pid = Process.spawn("/bin/sh", "-c", "echo to-io; echo to-file >&2", out: f, err: errout)
  Process.waitpid2(pid)
  p f.closed?
  f.close
  p File.read(output)
  p File.read(errout)

  # 11) A spawn with no options at all.
  pid = Process.spawn("/usr/bin/true")
  _, status = Process.waitpid2(pid)
  p status.exitstatus

  # 12) A path through a regular file raises Errno::ENOTDIR, for in: and out:.
  notdir = File.join(dir, "notdir")
  File.write(notdir, "x")
  [[:in, { in: File.join(notdir, "x") }], [:out, { out: File.join(notdir, "x") }]].each do |label, opts|
    begin
      Process.spawn("/bin/cat", **opts)
      puts "#{label} no raise"
    rescue SystemCallError => e
      puts "#{label} #{e.class} #{e.message.sub(dir, "DIR")}"
    end
  end

  # 13) A name longer than the filesystem allows raises Errno::ENAMETOOLONG.
  begin
    Process.spawn("/bin/cat", in: File.join(dir, "z" * 600))
    puts "no raise"
  rescue SystemCallError => e
    puts "#{e.class} #{e.message.sub(dir, "DIR").length}"
  end

  # 14) The message carries the whole path, however long.
  begin
    Process.spawn("/bin/cat", in: File.join(dir, "a" * 200, "b" * 200, "c" * 200))
    puts "no raise"
  rescue SystemCallError => e
    puts "#{e.class} #{e.message.sub(dir, "DIR").length} #{e.message[-12..]}"
  end

  File.delete(input, output, errout, notdir)
end
