require "openssl"
require "base64"
require "json"

def hx(s) = [s].pack("H*")
def b64u(bin) = Base64.urlsafe_encode64(bin, padding: false)

# RFC 8291's application-server key, reused here because its public half is
# published: a VAPID header's k= parameter is exactly those 65 bytes.
AS_PRIV = hx("c9f58f89813e9f8e872e71f42aa64e1757c9254dcc62b72ddc010bb4043ea11c")
AS_PUB  = hx("04fe33f4ab0dea71914db55823f73b54948f41306d920732dbb9a59a53286482200e597a7b7bc260ba1c227998580992e93973002f3012a28ae8f06bbb78e5ec0f")

key = OpenSSL::PKey::EC.from_private_bytes("prime256v1", AS_PRIV)

# A VAPID (RFC 8292) Authorization header, end to end.
header = JSON.generate({ "typ" => "JWT", "alg" => "ES256" })
claims = JSON.generate({ "aud" => "https://push.example.net",
                         "exp" => 1735689600,
                         "sub" => "mailto:ops@example.com" })
signing_input = "#{b64u(header)}.#{b64u(claims)}"
p signing_input
p b64u(key.public_key_bytes) == "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"

sig = key.sign_raw("SHA256", signing_input)
# ES256 is 64 bytes of r || s, which is 86 unpadded base64url characters. A DER
# signature would be 70-72 bytes here and base64url just as cleanly, which is
# why the length is asserted rather than assumed.
p sig.bytesize
p b64u(sig).bytesize
jwt = "#{signing_input}.#{b64u(sig)}"
p jwt.split(".").length
p key.verify_raw("SHA256", sig, signing_input)

# A verifier holds only the public bytes, which is the whole point of the
# public-only key: this is the side a push service is on.
pub = OpenSSL::PKey::EC.from_public_bytes("prime256v1", AS_PUB)
p pub.public_only?
p pub.public_key_bytes == AS_PUB
p pub.verify_raw("SHA256", sig, signing_input)

# ECDSA is randomised, so two signatures over the same input differ and both
# verify. That is why this test verifies rather than comparing to a vector.
sig2 = key.sign_raw("SHA256", signing_input)
p sig != sig2
p pub.verify_raw("SHA256", sig2, signing_input)

# --- what must NOT verify ---

p pub.verify_raw("SHA256", sig, signing_input + "x")   # different data
# Mangle r by FLIPPING its first byte, not by zeroing it: r is random per
# signature, so about one signature in 256 already begins with 0x00 and the
# "mangled" one was the original -- it verified, and this test failed roughly
# that often. An xor always changes the byte.
p pub.verify_raw("SHA256", ((sig.getbyte(0) ^ 0xff).chr) + sig.byteslice(1, 63), signing_input)  # mangled r
p pub.verify_raw("SHA256", sig.byteslice(0, 63), signing_input)  # wrong length
p pub.verify_raw("SHA256", "", signing_input)
# Another key's signature over the same bytes.
other = OpenSSL::PKey::EC.generate("prime256v1")
p pub.verify_raw("SHA256", other.sign_raw("SHA256", signing_input), signing_input)
p other.verify_raw("SHA256", sig, signing_input)

# P-384 signs and verifies at its own width: 48-byte halves, 96 in all.
k384 = OpenSSL::PKey::EC.generate("secp384r1")
s384 = k384.sign_raw("SHA256", "msg")
p s384.bytesize
p k384.verify_raw("SHA256", s384, "msg")

# --- refusals ---

begin
  pub.sign_raw("SHA256", "msg")
rescue OpenSSL::PKey::ECError => e
  puts "ECError: #{e.message}"
end

begin
  pub.dh_compute_key(AS_PUB)
rescue OpenSSL::PKey::ECError => e
  puts "ECError: #{e.message}"
end

begin
  OpenSSL::PKey::EC.from_public_bytes("prime256v1", AS_PUB.byteslice(0, 64) + hx("ff"))
rescue OpenSSL::PKey::ECError => e
  puts "ECError: #{e.message}"
end

begin
  OpenSSL::PKey::EC.new("prime256v1", "")
rescue OpenSSL::PKey::ECError => e
  puts "ECError: #{e.message}"
end

begin
  key.sign_raw("MD5", "msg")
rescue OpenSSL::OpenSSLError => e
  puts "#{e.class}: #{e.message}"
end
