# `s[/re/, n]` on a receiver typed `String | nil`: the typed emitter answers
# the capture inline, the boxed path read the two operands as an integer
# slice and raised TypeError on the Regexp. campfire's
# `response.headers["Link"][/<(.*)>/, 1]` -- a read off a
# Hash[String, String] -- is the caller.
def pick(ok)
  ok ? "<http://x/y?before=3>; rel=\"next\"" : nil
end

v = pick(true)
p v[/<(.*)>/, 1]
p v[/<(.*)>/, 0]
p v[/before=(\d+)/, 1]
p v[/nothing/, 1]
p v[/<(.*)>/, 4]
h = { "link" => "<http://x/y?before=3>; rel=\"next\"" }
p h["link"][/<(.*)>/, 1]
