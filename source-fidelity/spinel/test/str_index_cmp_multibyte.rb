# `s[i] == "c"` is folded into a raw byte load, which is the character at
# index i only while every character before i is one byte wide. Without a
# guard the comparison read the second byte of a multi-byte character and
# answered false for a character the same expression prints (#4239).
p "說*.rb"[1] == "*"

s = "a說*"
STAR = "*"
p s[2] == "*"
p((c = s[2]) == "*")
p s[2] == STAR
p s[2].eql?("*")
p s[2, 1] == "*"
p s.chars[2] == "*"
p(s[2] != "*")

# the all-ASCII shapes the fold exists for still answer, and still fold
p "abc"[1] == "b"
p "abc"[1] == "c"
p "abc"[1] != "b"

# a negative index counts from the end, as CRuby does
p "abc"[-1] == "c"
p "a說*"[-1] == "*"

# past the end is nil, which equals nothing and differs from everything
p "abc"[5] == "b"
p("abc"[5] != "b")

# an index computed at run time, over a string that gains a wide character
t = "a" + "說" + "*"
i = 2
p t[i] == "*"

# the receiver is evaluated once
n = 0
def bump(box)
  box[0] += 1
  "ab"
end
box = [0]
p bump(box)[1] == "b"
p box[0]
