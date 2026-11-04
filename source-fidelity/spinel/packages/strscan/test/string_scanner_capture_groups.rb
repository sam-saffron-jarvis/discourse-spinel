require "strscan"
s = StringScanner.new("foobar")
s.scan(/(f)(o+)/)
puts s[0].inspect
puts s[1].inspect
puts s[2].inspect
puts s[5].inspect
