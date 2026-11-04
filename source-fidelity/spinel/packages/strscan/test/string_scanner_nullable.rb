# StringScanner's string-returning methods return nil (not "") on a
# miss / EOS / no-last-match, matching CRuby. The matched (non-nil)
# result is a first-class string usable in every string operation.
require "strscan"

# scan / check / scan_until: nil on miss
s = StringScanner.new("hello world")
p s.scan(/x/)            # nil
p s.check(/x/)           # nil
p s.scan(/hello/)        # "hello"
p s.check(/ /)           # " "
p s.scan_until(/o/)      # " wo"
p s.scan_until(/zzz/)    # nil

# matched / pre_match / post_match
s2 = StringScanner.new("foobarbaz")
p s2.matched             # nil (no match yet)
s2.scan(/foo/)
p s2.matched             # "foo"
p s2.pre_match           # ""
p s2.post_match          # "barbaz"
s2.scan(/bar/)
p s2.pre_match           # "foo"

# getch: nil at EOS
s3 = StringScanner.new("ab")
p s3.getch               # "a"
p s3.getch               # "b"
p s3.getch               # nil

# [] capture group: nil out of range
s4 = StringScanner.new("2026-06-05")
s4.scan(/(\d+)-(\d+)/)
p s4[0]                  # "2026-06"
p s4[1]                  # "2026"
p s4[9]                  # nil

# A matched result behaves as a plain string across every operation.
s5 = StringScanner.new("key=val")
m = s5.scan(/\w+/)       # "key" : string?
puts(m + "!")            # concat
puts(m * 2)              # repeat
puts(m == "key")         # eq
puts(m < "z")            # compare
puts([m].length)         # array-literal element
acc = []
acc << m                 # array push
puts acc.length
h = {}
h[m] = 1                 # hash key
puts h.length
puts m.to_sym.inspect    # to_sym
puts "[#{m}]"            # interpolation

# truthiness + || default
puts "truthy" if s5.scan(/=/)
puts(s5.scan(/zzz/) || "default")

# The full operator set on a matched result.
s6 = StringScanner.new("mno")
w = s6.scan(/mno/)       # "mno"
puts(w > "a")            # true
puts(w <= "mno")         # true
puts(w >= "z")           # false
puts(w.between?("a", "z")) # true
fmt = StringScanner.new("%d")
pat = fmt.scan(/%d/)     # "%d"
puts(pat % 7)            # "7"

# A nil result (miss) flows through operators CRuby treats as valid.
miss = StringScanner.new("abc").scan(/zzz/)  # nil
puts("[#{miss}]")        # "[]" -- nil interpolates to ""
puts(miss == "abc")      # false
puts(miss != "abc")      # true
puts(miss.nil?)          # true
