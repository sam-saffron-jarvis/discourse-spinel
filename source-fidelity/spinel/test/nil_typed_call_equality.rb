# Comparing a concrete operand with a call the analyzer proved returns nil.
#
# `"image/png" != fetch.content_type` was refused at compile time while
# `got = fetch.content_type; "image/png" != got` compiled and answered
# correctly (#4415). The answers were never the problem: the emitter's nil
# path already knew what every operand type compares to nil as, including a
# nullable heap slot that really is nil. What it asked was whether the NODE
# was a `NilNode`, so a nil-TYPED call did not reach it and fell through to
# the "unsupported equality" refusal at the end of the chain.
#
# A literal nil and a nil-typed call differ in one way that matters: the call
# has to be EVALUATED. Ruby's order is receiver then argument, and that holds
# whichever side the call is on, so the arms below check the side effects and
# their order as well as the answers.
#
# The nullable-receiver line is the one that rules out answering this with a
# constant. `H.new.s` is a String-typed slot holding nil, and CRuby says
# nil == nil, so a fold to "a String is never nil, therefore unequal" would be
# a silent wrong answer rather than a refusal.
class Fetch
  def content_type
    nil
  end

  def loud
    puts "evaluated"
    nil
  end
end

class Holder
  def initialize
    @s = nil
  end

  def s
    @s
  end
end

class Overrides
  def ==(other)
    puts "override ran"
    true
  end
end

def left
  puts "left"
  "image/png"
end

def right
  puts "right"
  nil
end

f = Fetch.new

# the reported shape, both operators and both sides
p("image/png" == f.content_type)
p("image/png" != f.content_type)
p(f.content_type == "image/png")
p(f.content_type != "image/png")

# the call still runs, in either position
p("image/png" == f.loud)
p(f.loud == "image/png")

# receiver before argument
p(left == right)

# every operand kind the nil path knows
p(1 == f.content_type)
p(2.5 != f.content_type)
p(:sym != f.content_type)
p([1, 2] == f.content_type)
p({ "a" => 1 } != f.content_type)
p(true != f.content_type)

# a nullable slot that IS nil: equal, not "a String is never nil"
p(Holder.new.s == f.content_type)
p(Holder.new.s != f.content_type)

# a user `==` still owns the comparison
p(Overrides.new == f.content_type)

# both sides nil-typed keeps answering as it did
p(f.content_type == f.content_type)
p(f.content_type != f.content_type)
