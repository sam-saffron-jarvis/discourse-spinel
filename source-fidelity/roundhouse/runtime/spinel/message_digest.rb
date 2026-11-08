# frozen_string_literal: true
# Shared Ruby cryptographic primitives for native Spinel AND identical-lowered
# CRuby. Use the real OpenSSL API available in both runtimes, not ffi_func
# declarations which CRuby cannot load. No compatibility-file swap is required.
require "openssl"
require "securerandom"

module MessageDigest
  def self.hmac_sha1_hex(key, msg)
    OpenSSL::HMAC.hexdigest("SHA1", key, msg)
  end

  def self.hmac_sha256_hex(key, msg)
    OpenSSL::HMAC.hexdigest("SHA256", key, msg)
  end

  def self.hmac_sha256(key, msg)
    OpenSSL::HMAC.digest("SHA256", key, msg)
  end

  def self.secure_random_bytes(n)
    SecureRandom.random_bytes(n)
  end

  def self.secure_compare(a, b)
    return false if a.bytesize != b.bytesize
    diff = 0
    i = 0
    while i < a.bytesize
      diff = diff | (a.getbyte(i) ^ b.getbyte(i))
      i += 1
    end
    diff == 0
  end

  def self.pbkdf2_sha256(secret, salt, iters, dklen)
    OpenSSL::KDF.pbkdf2_hmac(secret, salt: salt, iterations: iters, length: dklen, hash: "SHA256")
  end

  def self.aes_256_gcm_encrypt(key, iv, plain)
    c = OpenSSL::Cipher.new("aes-256-gcm")
    c.encrypt
    c.key = key
    c.iv = iv
    c.auth_data = ""
    ct = c.update(plain) + c.final
    ct + c.auth_tag
  end

  def self.aes_256_gcm_decrypt(key, iv, ct, tag)
    return "" if tag.bytesize != 16
    c = OpenSSL::Cipher.new("aes-256-gcm")
    c.decrypt
    c.key = key
    c.iv = iv
    c.auth_tag = tag
    c.auth_data = ""
    begin
      c.update(ct) + c.final
    rescue OpenSSL::OpenSSLError
      # The runtimes name the GCM tag failure differently, but both errors
      # inherit OpenSSLError. Constructor/key/IV errors above still propagate.
      ""
    end
  end
end
