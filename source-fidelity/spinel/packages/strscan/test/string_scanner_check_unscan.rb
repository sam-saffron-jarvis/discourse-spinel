require "strscan"
# StringScanner#check must save the pre-match position (like #scan) so that
# a following #unscan rewinds to just before the check, not to the start.

s = StringScanner.new("hello world")
s.scan(/hello/)          # pos -> 5
s.check(/ /)             # pos stays 5, but last_pos must become 5
puts s.pos               # 5
s.unscan
puts s.pos               # 5, not 0

# check also feeds pre_match / post_match, which key off the saved position.
t = StringScanner.new("hello world")
t.scan(/hello/)
t.check(/ /)
puts t.pre_match.inspect   # "hello"
puts t.post_match.inspect  # "world"

# unscan rewinds to the most recent check, not the first scan.
u = StringScanner.new("ab cd")
u.scan(/ab/)
u.check(/ /)
u.unscan
puts u.pos               # 2
