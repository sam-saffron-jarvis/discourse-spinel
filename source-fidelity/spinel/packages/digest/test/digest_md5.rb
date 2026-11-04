# Digest::MD5 beside the SHA pair: hexdigest, the raw 16 digest bytes, and
# base64digest on all three classes. MD5 is what Active Storage's direct
# upload declares a blob's checksum with (#4631).
require "digest"

puts Digest::MD5.hexdigest("hello!")
puts Digest::MD5.hexdigest("")
puts Digest::MD5.hexdigest("abc")
puts Digest::MD5.hexdigest("The quick brown fox jumps over the lazy dog")
# one block exactly, the padding boundary, and past it
puts Digest::MD5.hexdigest("a" * 55)
puts Digest::MD5.hexdigest("a" * 56)
puts Digest::MD5.hexdigest("a" * 64)
puts Digest::MD5.hexdigest("a" * 1000)
# binary input with an embedded NUL survives intact
bin = ["00ff10a0"].pack("H*")
puts Digest::MD5.hexdigest(bin)

d = Digest::MD5.digest("hello!")
puts d.bytesize
puts d.encoding.to_s
puts(d.unpack("C*").map { |b| b.to_s(16).rjust(2, "0") }.join == Digest::MD5.hexdigest("hello!"))
puts(d == ["5a8dd3ad0756a93ded72b823b19dd877"].pack("H*"))

puts Digest::MD5.base64digest("hello!")
puts Digest::MD5.base64digest("")
puts Digest::SHA1.base64digest("hello!")
puts Digest::SHA256.base64digest("hello!")
puts Digest::SHA256.base64digest("")
