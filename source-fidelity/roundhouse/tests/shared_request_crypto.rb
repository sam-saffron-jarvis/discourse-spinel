# frozen_string_literal: true
require_relative "../runtime/spinel/message_digest"
def hex(bytes)
  bytes.bytes.map { |byte| byte.to_s(16).rjust(2, "0") }.join
end
puts MessageDigest.hmac_sha1_hex("k\0ey", "m\0sg")
puts MessageDigest.hmac_sha256_hex("k\0ey", "m\0sg")
puts hex(MessageDigest.hmac_sha256("k\0ey", "m\0sg"))
puts hex(MessageDigest.pbkdf2_sha256("password\0x", "salt\0y", 3, 64))
key = MessageDigest.pbkdf2_sha256("source", "salt", 2, 32)
iv = "123456789012"
plain = "message\0body"
sealed = MessageDigest.aes_256_gcm_encrypt(key, iv, plain)
ct = sealed.byteslice(0, sealed.bytesize - 16)
tag = sealed.byteslice(sealed.bytesize - 16, 16)
raise "GCM round trip" unless MessageDigest.aes_256_gcm_decrypt(key, iv, ct, tag) == plain
raise "GCM short tag accepted" unless MessageDigest.aes_256_gcm_decrypt(key, iv, ct, tag.byteslice(0, 15)) == ""
raise "GCM wrong tag accepted" unless MessageDigest.aes_256_gcm_decrypt(key, iv, ct, "x" * 16) == ""
raise "compare" unless MessageDigest.secure_compare("a\0b", "a\0b") && !MessageDigest.secure_compare("a\0b", "a\0c")
raise "entropy length" unless MessageDigest.secure_random_bytes(32).bytesize == 32
puts hex(sealed)
puts "PASS identical shared crypto including NUL bytes, authentication failures and real entropy"
