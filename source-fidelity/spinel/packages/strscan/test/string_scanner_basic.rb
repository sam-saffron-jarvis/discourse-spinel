require "strscan"
# Issue #845 / #812: StringScanner core methods.

s = StringScanner.new("hello world")
puts s.scan(/hello/).inspect
puts s.matched?.inspect
puts s.matched.inspect
puts s.pos
puts s.pre_match.inspect
puts s.post_match.inspect

# check doesn't advance pos.
puts s.check(/ /).inspect
puts s.pos       # still 5

# scan_until walks forward to a delimiter.
s2 = StringScanner.new("alpha;beta;gamma")
puts s2.scan_until(/;/).inspect
puts s2.pos
puts s2.rest.inspect

# getch / peek / eos?.
s3 = StringScanner.new("abc")
puts s3.getch.inspect
puts s3.peek(2).inspect
puts s3.eos?.inspect
s3.terminate
puts s3.eos?.inspect

# unscan rewinds the last successful scan.
s4 = StringScanner.new("hello")
s4.scan(/he/)
puts s4.pos
s4.unscan
puts s4.pos
