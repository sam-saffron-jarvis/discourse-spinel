# A File read out of a mixed container is a boxed handle, and the poly-IO
# dispatch only knew a few names: the descriptor surface -- stat, seek, tell,
# pos, pread, pwrite, fsync -- fell through to the unresolved-call gate and
# raised NoMethodError, where the same call on a typed handle works. An fd
# table is exactly this shape (0/1/2 an IO, the rest Files).
path = "spinel_poly_io_#{Process.pid}.tmp"
File.write(path, "hello world")
fds = { 0 => $stdin, 3 => File.open(path, File::RDONLY) }
io = fds[3]
p io.stat.size
p io.tell
p io.seek(6)
p io.pos
p io.read(5)
p io.pread(5, 0)
p io.eof?
p io.fileno.is_a?(Integer)
io.close

w = { 3 => File.open(path, "r+") }[3]
p w.pwrite("HELLO", 0)
p w.fsync
w.close
p File.read(path)

# ...and the typed receiver still answers exactly the same
t = File.open(path, File::RDONLY)
p t.stat.size
p t.seek(6)
p t.pos
p t.pread(5, 0)
t.close
File.unlink(path)
