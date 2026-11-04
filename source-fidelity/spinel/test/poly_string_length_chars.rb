# String#length and #size answer CHARACTERS. A receiver the inference widened
# to poly went through sp_poly_length, whose answer is the BYTE count -- what
# its container and iteration callers want, and wrong for this method. The two
# agree while the string is all ASCII and part company at the first wider
# character, so the same body answered 5 for a narrowed receiver and 7 for a
# widened one (#4251).
def narrowed(x)
  x.length
end

def widened(x)
  x.length
end

p narrowed("a — b")
p widened(true ? "a — b" : nil)

# the whole family on a widened receiver
def family(x)
  [x.length, x.size, x.bytesize, x.chars.length]
end

p family(true ? "a — b" : nil)
p family(true ? "abc" : nil)
p family(true ? "日本語" : nil)

# a shared-mutable handle carried the same way
def two(x)
  [x.length, x.size]
end

s = String.new("a — b")
p two(true ? s : nil)

# the container kinds keep counting elements, not bytes
p two(true ? [1, 2, 3] : nil)
p two(true ?({ "a" => 1, "b" => 2 }) : nil)
p two(true ? "" : nil)
