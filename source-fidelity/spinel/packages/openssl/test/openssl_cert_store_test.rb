# X509::Store construction, set_default_paths, and SSLContext#cert_store round-trip

require "openssl"

# 1. Store construction and set_default_paths
store = OpenSSL::X509::Store.new
store.set_default_paths
p ["set_default_paths", "ok"]

# 2. ctx.cert_store round-trip
ctx = OpenSSL::SSL::SSLContext.new
ctx.cert_store = store
p ["ctx.cert_store after set", ctx.cert_store == store]

# 3. nil default leaves previous verify path alone
ctx2 = OpenSSL::SSL::SSLContext.new
p ["ctx2.cert_store default", ctx2.cert_store.nil?]

ctx2.verify_mode = OpenSSL::SSL::VERIFY_PEER
p ["ctx2.verify_mode before store", ctx2.verify_mode]

ctx2.cert_store = store
p ["ctx2.verify_mode after store", ctx2.verify_mode]
p ["ctx2.cert_store after set", ctx2.cert_store == store]

# 4. Multiple contexts can share the same store (reference counting)
ctx3 = OpenSSL::SSL::SSLContext.new
ctx3.cert_store = store
p ["ctx3 shares store", ctx3.cert_store == store]

puts "end"