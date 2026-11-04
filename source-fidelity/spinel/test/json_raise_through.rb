require "json"

# A #to_json that can only raise is still called. CRuby's json calls #to_json
# on every value before it looks at anything else, so the exception is what
# JSON.generate answers -- for the object itself, and for one nested anywhere
# inside the document.
class Boom
  def to_json(*args)
    raise ArgumentError, "boom"
  end
end

# The same method, able to answer as well as raise, is the shape that already
# worked: it must keep working in both directions.
class Sometimes
  def initialize(fail)
    @fail = fail
  end

  def to_json(*args)
    raise ArgumentError, "sometimes" if @fail
    "1"
  end
end

# A walk inside a walk: the inner one raises, and the outer one is left holding
# the document it had built so far.
$deep = []
$deep << $deep

class Nested
  def to_json(*args)
    JSON.pretty_generate($deep)
    "0"
  end
end

# A #to_json need not raise to leave the walk behind: a throw and a proc's
# return jump over its frame the same way, and what the walk was holding has to
# survive that too -- the raise that comes after is where a buffer left dangling
# would show up.
class Thrower
  def to_json(*args)
    throw :out, 1
  end
end

class Returner
  def to_json(*args)
    $ret.call
    "1"
  end
end

# A #to_json with a block parameter, and a private one, are not dispatched --
# here or before this change. CRuby calls the first and skips the second. The
# lines below are here so both shapes stay compilable and neither raises.
class Blocky
  def to_json(*args, &blk)
    raise ArgumentError, "blocky"
  end
end

class Hidden
  def to_json(*args)
    raise ArgumentError, "hidden"
  end
  private :to_json
end

def answer
  yield
rescue => e
  "#{e.class}: #{e.message}"
end

# The same, for a walk that was left by a throw or a proc's return rather than
# by a raise: what the raise below reports is whether the walk left anything
# behind that the next unwind would trip over.
def raises_after
  yield
  raise "after"
rescue => e
  "#{e.class}: #{e.message}"
end

puts answer { JSON.generate(Boom.new) }
puts answer { JSON.generate(["x", Boom.new, "y"]) }
puts answer { JSON.pretty_generate(["x", Boom.new, "y"]) }
puts answer { JSON.generate(["a", { "k" => Boom.new }, "b"]) }
puts answer { JSON.generate([[[Boom.new]]]) }
puts answer { JSON.generate(["x", Sometimes.new(false), "y"]) }
puts answer { JSON.generate(["x", Sometimes.new(true), "y"]) }
puts answer { JSON.pretty_generate(["x", Sometimes.new(false), "y"]) }
puts answer { JSON.generate(["x", Nested.new, "y"]) }

# Every one of those raises leaves a walk holding a document buffer. Two
# hundred of them, over a document large enough that a buffer kept per raise
# would be worth megabytes, and the answer is still the same one.
$ret = nil

def returns_early
  $ret = proc { return "the proc returned out of the walk" }
  JSON.pretty_generate(["x", Returner.new, "y"])
  "not reached"
end

def caught
  catch(:out) { JSON.generate(["x", Thrower.new, "y"]) }
  "no raise after the throw"
rescue => e
  "#{e.class}: #{e.message}"
end

puts caught
puts raises_after { catch(:out) { JSON.generate(["x", Thrower.new, "y"]) } }
puts returns_early
puts raises_after { returns_early }
JSON.generate(["x", Blocky.new, "y"]) rescue nil   # CRuby calls it and raises; Spinel does not
puts answer { JSON.generate(["x", Hidden.new, "y"]); "no raise" }

# The document itself is one of the things the walk has to hold: a caller that
# hands over an expression keeps it nowhere else, and the walk allocates from
# its first escaped string onward. Eight hundred fresh arrays, each checked
# against its own last element -- on master three of them come back with the
# tail serialized as null, on a release build with no GC stress at all.
def fresh(i)
  a = []
  40.times { |j| a << "s#{i}-#{j}" }
  a
end

wrong = 0
800.times do |i|
  # bound to a local first: a String receiver held across an allocating
  # argument is a separate rule, and wrong on both trees under GC stress
  doc = JSON.generate(fresh(i))
  wrong += 1 unless doc.end_with?("\"s#{i}-39\"]")
end
puts "documents wrong: #{wrong}"

pad = "q" * 4000
big = []
40.times { big << pad }
big << Boom.new
40.times { big << pad }

seen = {}
200.times { seen[answer { JSON.generate(big) }] = true }
p seen.keys
