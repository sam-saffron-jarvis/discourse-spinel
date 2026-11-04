# A URI carrying a character RFC 3986 excludes is rejected, the way CRuby's
# parser rejects it -- an app can be relying on that rescue rather than on its
# own validation. Every line here answers what CRuby answers.
require "uri"

def parse(s)
  URI.parse(s)
  "parsed"
rescue URI::InvalidURIError
  "raised"
end

# The shape that surfaced it: with a space admitted, "exa mple.com" reads as an
# ordinary off-site host.
p parse("http://exa mple.com/ ")
p parse("http://example.com/a b")
p parse("http://example.com/<x>")
p parse(%(http://example.com/"x"))
p parse("http://example.com/x\u0000")
p parse("http://example.com/x\u007f")

# ...and the valid ones still parse, escapes included.
p parse("https://example.com/a/b?c=d#e")
p parse("http://user:pw@example.com:8080/x")
p parse("https://example.com/path%20with%20escape")
p parse("/rooms/1")
p parse("")

# Where a character is excluded is not uniform, and this follows CRuby: the
# QUERY takes any ASCII, the unwise set included, so a filter expression
# parses; the fragment and everything before the query do not.
p parse("http://example.com/?q=a|b")
p parse("http://example.com/?q=a b")
p parse("http://example.com/?q=<x>")
p parse("http://example.com/?q=a[1]")
p parse("http://example.com/#a[1]")
p parse("http://example.com/a[1]")

# a bracketed IPv6 host is the one place brackets belong
p parse("http://[::1]/x")
p parse("http://[::1]:8080/x")
p parse("http://user:pw@[2001:db8::1]:443/x")
p parse("http://exa[mple.com/")

# a byte outside ASCII is rejected everywhere, the query included
p parse("http://\u4f8b\u3048.jp/")
p parse("http://example.com/?q=\u00e9")
p parse("http://example.com/x\u00e9")
