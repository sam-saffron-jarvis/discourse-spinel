# A short IO#read(n) copies the bytes into a right-sized string, and that
# allocation can collect -- with the bytes just read held by nothing but a C
# local. On a small read the collector never fires and it looked right for
# years; asking for several MB and getting fewer freed the source and the copy
# read unmapped pages. Found compiling the Doom gem, whose WAD reader asks for
# a lump by offset and runs past the end of the file.
require "tmpdir"

path = File.join(Dir.tmpdir, "sp_short_read_#{Process.pid}.bin")
chunk = "x" * (1 << 20)
File.open(path, "wb") { |f| 6.times { f.write(chunk) } }

begin
  f = File.open(path, "rb")
  f.seek(4 << 20)
  s = f.read(8 << 20)
  p s.bytesize
  p s[0, 4].bytes
  p s[-4, 4].bytes
  f.close
ensure
  File.delete(path) if File.exist?(path)
end
