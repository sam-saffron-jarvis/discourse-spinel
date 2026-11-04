# CRuby's per-algorithm requires find the bundled digest package (#4828).
require "digest/md5"
require "digest/sha1"
require "digest/sha2"
puts Digest::MD5.hexdigest("abc")
puts Digest::SHA1.hexdigest("abc")
puts Digest::SHA256.hexdigest("abc")
