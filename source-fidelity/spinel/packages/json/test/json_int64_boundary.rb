# An integer at or past the signed 64-bit boundary parses to the Integer it
# spells: strtoll clamped one past the top back to the top, and the bottom
# and below it came back as a Bignum the generator wrote as null (#5042).
require "json"
%w[
  9223372036854775807
  9223372036854775808
  -9223372036854775808
  -9223372036854775809
  123456789012345678901234567890123456789012345678901234567890123456789012345
].each do |input|
  v = JSON.parse(input)
  puts "#{input} => #{JSON.generate(v)} #{v.to_s == input}"
end
p JSON.parse("[18446744073709551616, -1, 0]")
