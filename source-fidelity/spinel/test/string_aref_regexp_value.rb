# String#[] / #slice with the Regexp arriving as a VALUE (a parameter, a
# constant, a local) rather than a literal: the typed emitter served only
# the literal and sent a Regexp value to the integer slice arm, which raised
# TypeError at the operand (#4457).
def first_match(c, pattern)
  c[pattern, 0].to_s
end
def one_arg(c, pattern)
  c[pattern]
end
def group(c, pattern, n)
  c[pattern, n]
end
def named(c, pattern)
  [c[pattern, :ver], c[pattern, "ver"]]
end
def sliced(c, pattern)
  c.slice(pattern, 1)
end
BOT = /bot\/(?<ver>\d+\.\d+)/i
puts first_match("Googlebot/2.1", /bot/i)
p one_arg("Googlebot/2.1", /bot/i)
p one_arg("Googlebot/2.1", /cat/)
p group("Googlebot/2.1", /(bot)\/(\d)/, 1)
p group("Googlebot/2.1", /(bot)\/(\d)/, 2)
p group("Googlebot/2.1", /(bot)\/(\d)/, 3)
p group("nothing", /bot/, 0)
p named("Googlebot/2.1", BOT)
p named("Googlecat/2.1", BOT)
p sliced("Googlebot/2.1", /(bot)/)
re = /(\d+)\.(\d+)/
p "v 12.34"[re, 2]
p "v 12.34"[re]
