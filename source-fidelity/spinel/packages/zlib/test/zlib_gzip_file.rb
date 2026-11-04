# GzipWriter and GzipReader over a real file, and the interoperability that
# matters more than either: the file one of them writes is a .gz that gzip(1)
# and CRuby read, because the framing and the CRC are the format's, not ours.
require "zlib"
require "tmpdir"
require "fileutils"

dir = File.join(Dir.tmpdir, "sp_zlib_gz_#{Process.pid}")
FileUtils.mkdir_p(dir)
path = File.join(dir, "sample.txt.gz")

begin
  body = "line one\nline two\nline three\n" * 50

  Zlib::GzipWriter.open(path) do |gz|
    gz.write("line one\nline two\nline three\n" * 50)
  end
  p File.exist?(path)
  p File.size(path) < body.bytesize

  # The magic is gzip's, not a zlib header
  head = File.binread(path).bytes[0, 3]
  p head

  Zlib::GzipReader.open(path) do |gz|
    p gz.read == body
  end

  Zlib::GzipReader.open(path) do |gz|
    p gz.read(8)
    p gz.read(9)
    p gz.eof?
  end

  p Zlib::GzipReader.open(path) { |gz| gz.readlines.length }

  # gunzip of the same bytes agrees with the reader
  p Zlib.gunzip(File.binread(path)) == body
ensure
  FileUtils.rm_rf(dir)
end
p Dir.exist?(dir)
