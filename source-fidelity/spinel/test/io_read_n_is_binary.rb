# IO#read(n) answers ASCII-8BIT bytes whatever mode the handle was opened in,
# and so do #pread and #readpartial. It is not a label: indexing a text string
# is by CHARACTER, so `data[4, 4]` over bytes whose first byte happens to be a
# UTF-8 lead byte slid the window a byte to the right and unpacked the wrong
# fields. A WAD directory entry read that way named "ODES" with a nonsense size.
# A read with NO length carries the handle's encoding instead, so only a binary
# handle answers binary there.
require "tmpdir"

path = File.join(Dir.tmpdir, "sp_read_n_binary_#{Process.pid}.bin")
# 0xD4 0x9F is a well-formed two-byte UTF-8 sequence: character indexing sees
# one character where byte indexing sees two.
File.open(path, "wb") { |f| f.write("\xD4\x9F\x01\x00|J\x00\x00NODES\x00\x00\x00") }

begin
  f = File.open(path, "rb")
  data = f.read(16)
  p data.bytesize
  p data[0, 4].bytes
  p data[4, 4].bytes
  p data[8, 8].bytes
  p data.encoding.to_s
  f.close

  g = File.open(path)               # text mode: read(n) is binary all the same
  d2 = g.read(16)
  p d2[0, 4].bytes
  p d2.encoding.to_s
  g.close

  h = File.open(path, "rb")
  p h.read(0).encoding.to_s
  p h.pread(4, 0).bytes
  p h.pread(4, 0).encoding.to_s
  p h.readpartial(4).bytes
  p h.readpartial(4).encoding.to_s
  h.close

  # No length: the handle's own encoding.
  i = File.open(path, "rb")
  p i.read.encoding.to_s
  i.close
  j = File.open(path)
  p j.read.encoding.to_s
  j.close
ensure
  File.delete(path) if File.exist?(path)
end
