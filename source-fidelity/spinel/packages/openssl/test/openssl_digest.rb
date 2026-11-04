# OpenSSL::Digest and OpenSSL::HMAC over the runtime's own crypto. Every hash
# below is diffed against CRuby's, which is the point: these must be the same
# bytes, not merely the same shape.
#
# The HMAC-MD5 case is a subset boundary rather than a diff: CRuby carries it
# and the runtime's crypto does not (its MD5 is the digest alone), so it
# raises where CRuby answers. It raises the class CRuby raises for an
# algorithm it does not have, so a program that rescues
# OpenSSL::Digest::DigestError catches the same thing.
require "openssl"

p OpenSSL::Digest::SHA256.hexdigest("hi")
p OpenSSL::Digest::SHA1.hexdigest("hi")
p OpenSSL::Digest::SHA256.hexdigest("")
p OpenSSL::Digest::SHA256.digest("hi").bytesize
p OpenSSL::Digest::SHA1.digest("hi").bytesize
p OpenSSL::Digest::MD5.hexdigest("hi")
p OpenSSL::Digest::MD5.digest("hi").bytesize
p OpenSSL::HMAC.hexdigest("SHA256", "key", "msg")
p OpenSSL::HMAC.hexdigest("sha256", "key", "msg")
p OpenSSL::HMAC.hexdigest("SHA1", "key", "msg")
# A binary payload: the length rides the header, so an embedded NUL survives.
p OpenSSL::Digest::SHA256.hexdigest(String.new("a\0b"))

# The error hierarchy is CRuby's: DigestError and SSLError share a base.
p OpenSSL::Digest::DigestError.ancestors.take(3).map(&:to_s)
p OpenSSL::SSL::SSLError.ancestors.take(3).map(&:to_s)

begin
  OpenSSL::HMAC.hexdigest("MD5", "k", "m")
rescue OpenSSL::OpenSSLError => e
  puts "#{e.class}: #{e.message}"
end

# HMAC's raw half. The bytes are the same bytes the hex spelling names, which
# is the property that matters: hex(digest(...)) == hexdigest(...).
p OpenSSL::HMAC.digest("SHA256", "key", "msg").bytesize
p OpenSSL::HMAC.digest("SHA1", "key", "msg").bytesize
p OpenSSL::HMAC.digest("SHA256", "key", "msg").unpack1("H*") ==
  OpenSSL::HMAC.hexdigest("SHA256", "key", "msg")
p OpenSSL::HMAC.digest("SHA1", "key", "msg").unpack1("H*") ==
  OpenSSL::HMAC.hexdigest("SHA1", "key", "msg")
# A MAC with an embedded NUL is the case a NUL-terminated return would lose.
p OpenSSL::HMAC.digest("SHA256", "\x0b" * 20, "Hi There").unpack1("H*")

begin
  OpenSSL::HMAC.digest("MD5", "k", "m")
rescue OpenSSL::OpenSSLError => e
  puts "#{e.class}: #{e.message}"
end
