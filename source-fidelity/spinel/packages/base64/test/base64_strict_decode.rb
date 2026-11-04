require "base64"

# strict_decode64 (CRuby's unpack1("m0")) rejects anything the lax decoder would
# silently skip: a length that is not a multiple of 4, a newline or whitespace,
# out-of-alphabet bytes, and misplaced padding all raise ArgumentError. The lax
# decode64 stays permissive.
def sd(x); Base64.strict_decode64(x); end
def check(x)
  begin
    r = sd(x)
    puts "#{x.inspect} => #{r.inspect}"
  rescue ArgumentError => e
    puts "#{x.inspect} => AE: #{e.message}"
  end
end

check("U2VuZA==")     # "Send"
check("U2Vu")         # "Sen"
check("QQ==")         # "A"
check("")             # ""
check("U2VuZA==\n")   # AE (trailing newline)
check("U2V")          # AE (length not a multiple of 4)
check("U2VuZA")       # AE (unpadded)
check("QQ")           # AE (unpadded)
check("AB!C")         # AE (invalid char)
check("abcd\nefgh")   # AE (embedded newline)
check("  U2Vu")       # AE (leading spaces)

# The lax decoder is unaffected: it still skips a trailing newline.
p Base64.decode64("U2VuZA==\n")   # "Send"
