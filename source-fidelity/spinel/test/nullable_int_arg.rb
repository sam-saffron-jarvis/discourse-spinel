# A nil that arrives through an `Integer?` slot (a `String#index` miss) reaching
# a strict Integer argument -- an index, a count, a width -- is the nil CRuby
# refuses with "no implicit conversion from nil to integer", not the SP_INT_NIL
# sentinel folded as a number. The compile-time `s[nil]` already raised it at
# the emitter; the slot's nil now takes the same path, at the one funnel every
# strict Integer argument passes through, so the whole family answers alike
# rather than the index arms alone (#4896).
#
# A Range endpoint is the exception: `s[ix..]` with a nil ix is the beginless
# Range covering the receiver, exactly as the written-out `s[nil..]` is.
str = "Crystal"
ix = str.index("z")
a = [1, 2, 3]

def t(label)
  v = yield
  puts "#{label} => #{v.inspect}"
rescue TypeError => e
  puts "#{label} => #{e.class}: #{e.message}"
end

t("str[ix]")        { str[ix] }
t("str[ix, 2]")     { str[ix, 2] }
t("str.slice(ix)")  { str.slice(ix) }
t("str.byteslice")  { str.byteslice(ix) }
t("a[ix]")          { a[ix] }
t("a.at(ix)")       { a.at(ix) }
t("a.fetch(ix)")    { a.fetch(ix) }
t("str * ix")       { str * ix }
t("a.first(ix)")    { a.first(ix) }
t("a.take(ix)")     { a.take(ix) }
t("a.drop(ix)")     { a.drop(ix) }
t("a.rotate(ix)")   { a.rotate(ix) }
t("str.ljust(ix)")  { str.ljust(ix) }
t("str.center(ix)") { str.center(ix) }
t("Array.new(ix)")  { Array.new(ix) }

b = +"Crystal"
t("b[ix] = 'z'")    { b[ix] = "z"; b }
c = [1, 2, 3]
t("c[ix] = 9")      { c[ix] = 9; c }
t("c.insert(ix, 0)"){ c.insert(ix, 0) }

# a Range endpoint is an absent bound, not a conversion failure
t("str[ix..]")      { str[ix..] }
t("str[ix...]")     { str[ix...] }
t("str[0..ix]")     { str[0..ix] }
t("str[0...ix]")    { str[0...ix] }
t("str[ix..ix]")    { str[ix..ix] }
t("str[nil..]")     { str[nil..] }
t("a[ix..]")        { a[ix..] }
t("a[0..ix]")       { a[0..ix] }
t("a[0...ix]")      { a[0...ix] }
t("m[0...ix]")      { [1, "m", 3][0...ix] }
t("a[nil..2]")      { a[nil..2] }

# the sentinel still reads as nil, and a value that arrives keeps working
p ix.nil?
jx = str.index("y") ? 0 : 1
p str[jx]
p a[jx]
n = 0
n += 1 while n < 3   # a counter from a literal stays the bare index it was
p a[n - 1]

# a receiver with a side effect is evaluated once, though a nil or omitted
# end reads its length
$calls = 0
def recv_str = ($calls += 1; "Crystal")
p recv_str[1..ix], recv_str[2..], $calls
