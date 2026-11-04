# IO#pwrite sized its operand with strlen, so a String with an embedded NUL
# was cut at the first one -- no exception, the remaining bytes simply not
# written. IO#write has sized by the header length since #3540; pwrite is its
# positional twin and now makes the same String/non-String split.
# And a refused seek reported itself as a -1 return rather than the
# descriptor's error, so a caller rescuing Errno saw a successful seek.
path = "spinel_pwrite_#{Process.pid}.tmp"
File.write(path, "0" * 24)
io = File.open(path, "r+")
p io.pwrite("abcd", 0)
p io.pwrite("\x00\x01\x02\x03", 4)
p io.pwrite("ab\x00cd", 8)
p io.pwrite("\x00" * 4, 16)
n = 7
p io.pwrite(n.to_s, 20)          # a non-String operand still converts
io.close
p File.binread(path).bytes
# the write side, for the same bytes
io = File.open(path, "w")
p io.write("ef\x00gh")
io.close
p File.binread(path).bytes

io = File.open(path, "r")
begin; io.seek(-1, IO::SEEK_SET); rescue => e; p e.class; end
p io.seek(0, IO::SEEK_SET)
p io.seek(2, IO::SEEK_CUR)
p io.tell
io.close

File.unlink(path)
