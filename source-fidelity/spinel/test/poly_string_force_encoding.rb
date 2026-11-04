# `force_encoding`, `encode!` and `b` on a receiver typed `String | nil`: the
# String arms existed, the poly dispatch had no entry for them, so a String
# read out of a nilable slot answered NoMethodError at run time and was
# refused as a puts argument at compile time. campfire's
# `location.read_html.force_encoding("UTF-8")` is the caller; `read_html` is
# `fetch_html if valid?`, a `String | nil` by construction. (#4441)
# (Literals are frozen in spinel, so the strings here are built.)
def read(ok)
  ok ? String.new("<b>café</b>") : nil
end

s = read(true)
t = s.force_encoding("UTF-8")
puts t
puts s.force_encoding("UTF-8")
puts s.b.bytesize
p s.b.encoding.to_s
p s.encode!("UTF-8")
u = String.new("x")
v = read(true) ? u : nil
p v.force_encoding(Encoding::BINARY).encoding.to_s
n = read(false)
begin
  n.force_encoding("UTF-8")
rescue NoMethodError => e
  puts e.message
end
begin
  n.b
rescue NoMethodError => e
  puts e.message
end
